module Noko
  # A single piece of activity on the timeline. Every source produces these.
  #   ts     - Unix timestamp of the activity
  #   cmd    - human-readable line shown to Claude
  #   source - "shell" | "git" | "browser"
  Entry = Struct.new(:ts, :cmd, :source, keyword_init: true)
end
