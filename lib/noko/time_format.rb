module Noko
  # Helpers for the H:MM time format Noko uses.
  module TimeFormat
    module_function

    # Minutes (Integer/Float) => "H:MM"
    def format(minutes)
      h = (minutes / 60).floor
      m = (minutes % 60).round
      "#{h}:#{m.to_s.rjust(2, "0")}"
    end

    # "H:MM" => minutes (Integer), or nil when the string is malformed.
    def parse(value)
      return nil unless value.is_a?(String)

      m = value.match(/\A(\d+):(\d{2})\z/)
      return nil unless m

      hours = m[1].to_i
      mins = m[2].to_i
      return nil if mins >= 60

      (hours * 60) + mins
    end
  end
end
