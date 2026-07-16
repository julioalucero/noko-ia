module Noko
  module Sources
    # Reads the day's commits (by the current git user) from every repo under
    # BASE_DIR, tagging each with its ticket when one can be inferred.
    class Git
      TICKET = /\b([A-Z]+-\d+)\b/

      def initialize(date_str:, base_dir:)
        @date_str = date_str
        @base_dir = base_dir
      end

      def entries
        author = `git config user.email`.strip
        repos.flat_map { |repo| commits_for(repo, author) }
      end

      private

      def repos
        Dir.glob("#{@base_dir}/**/.git", File::FNM_DOTMATCH)
           .map { |g| File.dirname(g) }
           .reject { |r| r.include?("/.git/") }
      end

      def commits_for(repo, author)
        log = `git -C "#{repo}" log \
          --after="#{@date_str} 00:00:00" \
          --before="#{@date_str} 23:59:59" \
          --author="#{author}" \
          --format="%ai|%s|%D" \
          --all 2>/dev/null`

        log.each_line.filter_map do |line|
          parts = line.chomp.split("|", 3)
          next if parts.size < 2

          timestamp, message, refs = parts
          commit_time = Time.parse(timestamp) rescue nil
          next unless commit_time

          ticket = refs&.scan(TICKET)&.flatten&.first
          ticket ||= message.scan(TICKET).flatten.first
          cmd = ticket ? "git commit [#{ticket}] #{message}" : "git commit #{message}"

          Entry.new(ts: commit_time.to_i, cmd: cmd, source: "git")
        end
      end
    end
  end
end
