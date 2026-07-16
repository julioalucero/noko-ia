module Noko
  # Ties everything together: parse args, gather each source, build the
  # timeline, ask Claude, and print the report.
  class Runner
    BASE_DIR = File.expand_path("~/projects")

    def self.run(argv)
      new(argv).call
    end

    def initialize(argv)
      @date = parse_date(argv[0] || Date.today.strftime("%m-%d-%y"))
      @target_minutes = parse_target(argv[1])
    end

    def call
      config = Config.new
      label = @date.strftime("%B %-d, %Y")
      puts "\n📅  Analyzing activity for #{label}\n\n"

      timeline = Timeline.new(gather(config))
      if timeline.empty?
        puts "\n😶  No activity found for #{label}."
        return
      end

      puts ""
      prompt = Prompt.new(
        timeline: timeline,
        target_minutes: @target_minutes,
        prefix_to_project: config.prefix_to_project,
        date_label: label
      ).to_s

      puts "🤖  Asking Claude to analyze your activity...\n\n"
      entries = Claude.new(config.api_key).analyze(prompt, target_minutes: @target_minutes)

      Report.new(entries, date_label: label, target_minutes: @target_minutes).print
    end

    private

    def gather(config)
      day_start = Time.mktime(@date.year, @date.month, @date.day, 0, 0, 0).to_i
      day_end = day_start + 86_400
      date_str = @date.strftime("%Y-%m-%d")

      shell = Sources::Shell.new(day_start: day_start, day_end: day_end).entries
      puts "🐚  Found #{shell.size} shell commands"

      git = Sources::Git.new(date_str: date_str, base_dir: BASE_DIR).entries
      puts "📦  Found #{git.size} git commits"

      browser = Sources::Browser.new(
        day_start: day_start, day_end: day_end, domains: config.browser_domains
      ).entries
      puts "🌐  Found #{browser.size} browser pages (after dropping glances)"

      shell + git + browser
    end

    def parse_date(arg)
      Date.strptime(arg, "%m-%d-%y")
    rescue ArgumentError
      abort "Invalid date format. Use MM-DD-YY, e.g. 04-28-26"
    end

    def parse_target(arg)
      hours =
        if arg.nil?
          8.0
        else
          begin
            value = Float(arg)
            abort "Invalid TARGET_HOURS. Use a positive number like 8 or 7.5" if value <= 0
            value
          rescue ArgumentError
            abort "Invalid TARGET_HOURS. Use a positive number like 8 or 7.5"
          end
        end
      (hours * 60).round
    end
  end

  def self.run(argv)
    Runner.run(argv)
  end
end
