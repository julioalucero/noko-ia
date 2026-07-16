module Noko
  # Merges entries from all sources into one sorted timeline and estimates the
  # total active time, ignoring long gaps (lunch/breaks).
  class Timeline
    MAX_GAP     = 90 # minutes — gaps larger than this are ignored
    TAIL_BUFFER = 30 # minutes — buffer credited to the last activity

    attr_reader :entries

    def initialize(entries)
      @entries = entries.sort_by(&:ts).uniq(&:ts)
    end

    def empty?
      @entries.empty?
    end

    def total_minutes
      total = 0
      @entries.each_cons(2) do |a, b|
        gap = (b.ts - a.ts) / 60.0
        total += gap if gap <= MAX_GAP
      end
      total + TAIL_BUFFER
    end
  end
end
