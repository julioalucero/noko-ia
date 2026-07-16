module Noko
  module Sources
    # Reads Brave's local history (Chromium SQLite schema) for the given day.
    # Only pages on the configured work domains are kept, aggregated per title
    # with a visit count and total dwell time. A page seen once for less than
    # GLANCE_MIN is treated as a glance (someone else's ticket, a stray link)
    # and dropped, so it never reaches the prompt as "work".
    class Browser
      DB = File.expand_path(
        "~/Library/Application Support/BraveSoftware/Brave-Browser/Default/History"
      )
      DWELL_CAP  = 30 * 60 # seconds — max time credited to a single page view
      GLANCE_MIN = 2 * 60  # seconds — a lone visit under this is just a glance

      def initialize(day_start:, day_end:, domains:)
        @day_start = day_start
        @day_end = day_end
        @domains = domains
      end

      def entries
        return [] if @domains.empty?
        return [] unless File.exist?(DB) && sqlite3?

        visits = read_visits
        return [] if visits.empty?

        aggregate(visits).filter_map { |title, page| to_entry(title, page) }
      end

      private

      def sqlite3?
        system("which sqlite3 > /dev/null 2>&1")
      end

      # Brave locks the DB while running, so query a copy.
      def read_visits
        tmp = "/tmp/noko-brave-#{@day_start}.db"
        return [] unless system("cp", DB, tmp)

        # Feed the query over stdin so no SQL passes through the shell
        # (the '' empty-string literal would break shell single-quoting).
        raw = IO.popen(["sqlite3", "-separator", "\t", tmp], "r+") do |io|
          io.puts query
          io.close_write
          io.read
        end
        parse(raw)
      ensure
        File.delete(tmp) if tmp && File.exist?(tmp)
      end

      # Chromium stores timestamps as microseconds since 1601-01-01 (WebKit
      # epoch). Note the single-quoted '' — in SQLite "" is an identifier.
      def query
        <<~SQL
          SELECT v.visit_time/1000000 - 11644473600 AS unixts, u.url, u.title
          FROM visits v JOIN urls u ON u.id = v.url
          WHERE v.visit_time/1000000 - 11644473600 >= #{@day_start}
            AND v.visit_time/1000000 - 11644473600 <  #{@day_end}
            AND u.title IS NOT NULL AND u.title != ''
          ORDER BY v.visit_time;
        SQL
      end

      # Every visit (all sites) so dwell can be bounded by the next visit to
      # *any* page — glancing at a work page then jumping to x.com dwells ~0.
      def parse(raw)
        raw.to_s.each_line.filter_map do |line|
          ts, url, title = line.chomp.split("\t", 3)
          next unless url && title

          { ts: ts.to_i, host: url[%r{\Ahttps?://([^/]+)}, 1].to_s, title: title }
        end
      end

      # Group work visits by title: { title => {ts, host, visits, dwell} }.
      # Dwell per view = time until the next visit, capped (idle tabs don't
      # count for the full time they sat open).
      def aggregate(visits)
        pages = {}
        visits.each_with_index do |v, i|
          next unless work?(v[:host])

          nxt = visits[i + 1]
          dwell = nxt ? [nxt[:ts] - v[:ts], DWELL_CAP].min : GLANCE_MIN
          dwell = 0 if dwell.negative?

          page = (pages[v[:title]] ||= { ts: v[:ts], host: v[:host], visits: 0, dwell: 0 })
          page[:visits] += 1
          page[:dwell]  += dwell
          page[:ts] = v[:ts] if v[:ts] < page[:ts] # place at first view
        end
        pages
      end

      def work?(host)
        @domains.any? { |d| host.include?(d) }
      end

      def to_entry(title, page)
        return nil if page[:visits] == 1 && page[:dwell] < GLANCE_MIN

        mins = (page[:dwell] / 60.0).round
        Entry.new(
          ts: page[:ts],
          cmd: "#{title} (#{page[:host]}) [#{page[:visits]}x, #{mins}min]",
          source: "browser"
        )
      end
    end
  end
end
