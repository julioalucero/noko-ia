module Noko
  module Sources
    # Reads the day's GitHub activity via the events API. Unlike browser
    # history, this is authoritative: a page visit tells you nothing, but a
    # review/comment/PR event means you actually did something. Commits are
    # left to the local git source (this would just duplicate them).
    class Github
      API = "https://api.github.com"

      # event type => verb used in the description
      VERBS = {
        "PullRequestReviewEvent"        => "reviewed",
        "PullRequestReviewCommentEvent" => "reviewed",
        "IssueCommentEvent"             => "commented on",
        "PullRequestEvent"              => "worked on",
        "IssuesEvent"                   => "worked on"
      }.freeze

      def initialize(day_start:, day_end:, token:)
        @day_start = day_start
        @day_end = day_end
        @token = token
      end

      def entries
        return [] if @token.to_s.empty?

        login = fetch_login
        return [] unless login

        aggregate(fetch_events(login))
      end

      private

      def fetch_login
        get("/user")&.dig("login")
      end

      # Events come back newest-first, 100 per page, capped at ~300 total by the
      # API. Stop paging once we've walked past the start of the day.
      def fetch_events(login)
        events = []
        (1..3).each do |page|
          batch = get("/users/#{login}/events?per_page=100&page=#{page}")
          break unless batch.is_a?(Array) && !batch.empty?

          events.concat(batch)
          oldest = parse_ts(batch.last["created_at"])
          break if oldest && oldest < @day_start
        end
        events
      end

      # Group all activity on a given PR/issue into one entry, so a review plus
      # its inline comments don't show up as a dozen lines.
      def aggregate(events)
        pages = {}
        events.each do |e|
          verb = VERBS[e["type"]]
          next unless verb

          ts = parse_ts(e["created_at"])
          next unless ts && ts >= @day_start && ts < @day_end

          item = e.dig("payload", "pull_request") || e.dig("payload", "issue")
          next unless item

          key = [e.dig("repo", "name"), item["number"]]
          page = (pages[key] ||= {
            ts: ts, verbs: [], title: item["title"],
            repo: e.dig("repo", "name"), number: item["number"]
          })
          page[:verbs] << verb
          page[:ts] = ts if ts < page[:ts]
        end

        pages.values.map { |p| to_entry(p) }
      end

      def to_entry(page)
        # "reviewed" wins over "commented on"/"worked on" when both happened.
        verb = page[:verbs].include?("reviewed") ? "reviewed" : page[:verbs].first
        Entry.new(
          ts: page[:ts],
          cmd: "github #{verb} ##{page[:number]} #{page[:title]} (#{page[:repo]})",
          source: "github"
        )
      end

      def parse_ts(str)
        Time.parse(str).to_i
      rescue ArgumentError, TypeError
        nil
      end

      def get(path)
        uri = URI("#{API}#{path}")
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{@token}"
        req["Accept"] = "application/vnd.github+json"
        req["User-Agent"] = "noko-ia"

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
        return nil unless res.code == "200"

        JSON.parse(res.body)
      rescue StandardError
        nil
      end
    end
  end
end
