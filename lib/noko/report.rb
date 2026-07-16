module Noko
  # Prints the final Noko time summary to the terminal.
  class Report
    WIDTH = 55

    def initialize(entries, date_label:, target_minutes:)
      @entries = entries
      @date_label = date_label
      @target_minutes = target_minutes
    end

    def print
      puts "=" * WIDTH
      puts "  Noko Time Summary — #{@date_label}"
      puts "=" * WIDTH
      puts "  Target total time:    #{TimeFormat.format(@target_minutes)}"
      puts "-" * WIDTH

      @entries.each do |e|
        puts "\n  ⏱  #{e["time"]}"
        puts "  📁  #{e["project"] || "(no project match)"}"
        puts "  📝  #{e["description"]}"
      end

      puts "\n" + "=" * WIDTH
      puts "  Copy-paste format (TIME | PROJECT | DESCRIPTION):"
      puts "-" * WIDTH

      @entries.each do |e|
        puts "#{e["time"]} | #{e["project"] || "???"} | #{e["description"]}"
      end

      puts ""
    end
  end
end
