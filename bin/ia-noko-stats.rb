#!/usr/bin/env ruby
# Usage: ruby bin/ia-noko-stats.rb [MM-DD-YY] [TARGET_HOURS]
# Defaults: today's date and 8 hours when omitted
# Example: ruby bin/ia-noko-stats.rb                 # today, 8h
# Example: ruby bin/ia-noko-stats.rb 04-28-26 8
# Example: ruby bin/ia-noko-stats.rb 04-28-26 7.5

require_relative "../lib/noko"

Noko.run(ARGV)
