module Noko
  module Sources
    # Reads commands from the zsh history file for the given day.
    class Shell
      HISTORY = File.expand_path("~/.zsh_history")

      def initialize(day_start:, day_end:)
        @day_start = day_start
        @day_end = day_end
      end

      def entries
        return [] unless File.exist?(HISTORY)

        result = []
        # zsh_history is read as ASCII-8BIT; scrub each command to valid UTF-8
        # so the prompt can be JSON-encoded later (commands may hold unicode).
        File.open(HISTORY, "r:ASCII-8BIT") do |f|
          f.each_line do |line|
            next unless line =~ /^:\s*(\d+):(\d+);(.+)/

            ts = $1.to_i
            next unless ts >= @day_start && ts < @day_end

            cmd = $3.strip.force_encoding("UTF-8").scrub("")
            result << Entry.new(ts: ts, cmd: cmd, source: "shell")
          end
        end
        result
      end
    end
  end
end
