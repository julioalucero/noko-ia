#!/usr/bin/env ruby
# Usage: ruby bin/ia-noko-stats.rb [MM-DD-YY] [TARGET_HOURS]
# Defaults: today's date and 8 hours when omitted
# Example: ruby bin/ia-noko-stats.rb                 # today, 8h
# Example: ruby bin/ia-noko-stats.rb 04-28-26 8
# Example: ruby bin/ia-noko-stats.rb 04-28-26 7.5

require "date"
require "time"
require "yaml"
require "json"
require "net/http"
require "uri"

# ── Load .env ─────────────────────────────────────────────────────────────────
env_file = File.expand_path(".env", File.dirname(__dir__))
if File.exist?(env_file)
  File.readlines(env_file).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    key, value = line.split("=", 2)
    ENV[key.strip] = value.strip if key && value
  end
end

# ── Config ────────────────────────────────────────────────────────────────────
DATE_ARG    = ARGV[0] || Date.today.strftime("%m-%d-%y")
TARGET_ARG  = ARGV[1]
MAX_GAP     = 90  # minutes — gaps larger than this are ignored (lunch/break)
DWELL_CAP   = 30 * 60 # seconds — max time credited to a single page view
GLANCE_MIN  = 2 * 60  # seconds — a single visit under this = a glance, ignored
CONFIG_FILE = File.expand_path("noko_projects.yml", File.dirname(__dir__))
BASE_DIR    = File.expand_path("~/projects")

target_hours = if TARGET_ARG.nil?
                 8.0
               else
                 begin
                   value = Float(TARGET_ARG)
                   abort "Invalid TARGET_HOURS. Use a positive number like 8 or 7.5" if value <= 0
                   value
                 rescue ArgumentError
                   abort "Invalid TARGET_HOURS. Use a positive number like 8 or 7.5"
                 end
               end
target_minutes = (target_hours * 60).round

# Load project mappings: { "TICKET_PREFIX" => "Noko Project Name" }
PREFIX_TO_PROJECT = {}
BROWSER_DOMAINS = []
if File.exist?(CONFIG_FILE)
  config = YAML.load_file(CONFIG_FILE)
  (config["projects"] || {}).each do |project, prefix|
    PREFIX_TO_PROJECT[prefix.upcase] = project if prefix
  end
  BROWSER_DOMAINS.concat(Array(config["browser_domains"]).compact.map(&:to_s))
else
  warn "⚠️  Config file not found: #{CONFIG_FILE}"
end

# Format minutes as H:MM
def format_time(minutes)
  h = (minutes / 60).floor
  m = (minutes % 60).round
  "#{h}:#{m.to_s.rjust(2, "0")}"
end

def parse_hmm_to_minutes(value)
  return nil unless value.is_a?(String)
  m = value.match(/\A(\d+):(\d{2})\z/)
  return nil unless m

  hours = m[1].to_i
  mins = m[2].to_i
  return nil if mins >= 60

  (hours * 60) + mins
end

# ── Parse date ────────────────────────────────────────────────────────────────
begin
  parsed = Date.strptime(DATE_ARG, "%m-%d-%y")
rescue ArgumentError
  abort "Invalid date format. Use MM-DD-YY, e.g. 04-28-26"
end

date_label = parsed.strftime("%B %-d, %Y")
date_str   = parsed.strftime("%Y-%m-%d")
day_start  = Time.mktime(parsed.year, parsed.month, parsed.day, 0, 0, 0).to_i
day_end    = day_start + 86400

puts "\n📅  Analyzing activity for #{date_label}\n\n"

# ── Read zsh history for that day ─────────────────────────────────────────────
zsh_history = File.expand_path("~/.zsh_history")
shell_entries = []

if File.exist?(zsh_history)
  File.open(zsh_history, "r:ASCII-8BIT") do |f|
    f.each_line do |line|
      next unless line =~ /^:\s*(\d+):(\d+);(.+)/
      ts  = $1.to_i
      # zsh_history is read as ASCII-8BIT; scrub to valid UTF-8 so the prompt
      # can be JSON-encoded later (commands may contain unicode bytes).
      cmd = $3.strip.force_encoding("UTF-8").scrub("")
      next unless ts >= day_start && ts < day_end
      shell_entries << { ts: ts, cmd: cmd, source: "shell" }
    end
  end
end

puts "🐚  Found #{shell_entries.size} shell commands"

# ── Read git commits for that day ─────────────────────────────────────────────
git_entries = []
repos = Dir.glob("#{BASE_DIR}/**/.git", File::FNM_DOTMATCH)
            .map { |g| File.dirname(g) }
            .reject { |r| r.include?("/.git/") }

git_author = `git config user.email`.strip

repos.each do |repo|
  log = `git -C "#{repo}" log \
    --after="#{date_str} 00:00:00" \
    --before="#{date_str} 23:59:59" \
    --author="#{git_author}" \
    --format="%ai|%s|%D" \
    --all 2>/dev/null`

  log.each_line do |line|
    parts = line.chomp.split("|", 3)
    next if parts.size < 2
    timestamp, message, refs = parts
    commit_time = Time.parse(timestamp) rescue next

    ticket = nil
    ticket = refs.scan(/\b([A-Z]+-\d+)\b/).flatten.first if refs
    ticket ||= message.scan(/\b([A-Z]+-\d+)\b/).flatten.first

    cmd = ticket ? "git commit [#{ticket}] #{message}" : "git commit #{message}"
    git_entries << { ts: commit_time.to_i, cmd: cmd, source: "git" }
  end
end

puts "📦  Found #{git_entries.size} git commits"

# ── Read Brave browser history for that day ───────────────────────────────────
# Reads page visits from the local SQLite history DB (Chromium schema).
# Only hosts matching BROWSER_DOMAINS are kept; titles are deduped to one entry
# per title per 15-minute window so reloads/tabs don't spam the timeline.
browser_entries = []
brave_db = File.expand_path(
  "~/Library/Application Support/BraveSoftware/Brave-Browser/Default/History"
)

if File.exist?(brave_db) && !BROWSER_DOMAINS.empty? && system("which sqlite3 > /dev/null 2>&1")
  # Brave locks the DB while running, so query a copy.
  tmp_db = "/tmp/noko-brave-#{parsed.strftime("%Y%m%d")}.db"
  if system("cp", brave_db, tmp_db)
    # Chromium stores timestamps as microseconds since 1601-01-01 (WebKit epoch).
    # Note the single-quoted '' for the empty string: in SQLite "" is an
    # identifier, not a string literal.
    query = <<~SQL
      SELECT v.visit_time/1000000 - 11644473600 AS unixts, u.url, u.title
      FROM visits v JOIN urls u ON u.id = v.url
      WHERE v.visit_time/1000000 - 11644473600 >= #{day_start}
        AND v.visit_time/1000000 - 11644473600 <  #{day_end}
        AND u.title IS NOT NULL AND u.title != ''
      ORDER BY v.visit_time;
    SQL

    # Feed the query over stdin so no SQL ever passes through the shell
    # (the '' empty-string literal would break shell single-quoting).
    raw = IO.popen(["sqlite3", "-separator", "\t", tmp_db], "r+") do |io|
      io.puts query
      io.close_write
      io.read
    end

    # Parse every visit (all sites) so dwell can be bounded by the next visit
    # to *any* page — glancing at a work page then jumping to x.com dwells ~0.
    visits = raw.to_s.each_line.map do |line|
      ts_str, url, title = line.chomp.split("\t", 3)
      next unless url && title
      { ts: ts_str.to_i, host: url[%r{\Ahttps?://([^/]+)}, 1].to_s, title: title }
    end.compact

    # Aggregate work visits by title: how many times, and total dwell time.
    # Dwell per view = time until the next visit, capped (idle tabs don't count).
    pages = {}
    visits.each_with_index do |v, i|
      next unless BROWSER_DOMAINS.any? { |d| v[:host].include?(d) }

      nxt   = visits[i + 1]
      dwell = nxt ? [nxt[:ts] - v[:ts], DWELL_CAP].min : GLANCE_MIN
      dwell = 0 if dwell.negative?

      p = (pages[v[:title]] ||= { ts: v[:ts], host: v[:host], visits: 0, dwell: 0 })
      p[:visits] += 1
      p[:dwell]  += dwell
      p[:ts] = v[:ts] if v[:ts] < p[:ts] # place on the timeline at first view
    end

    # Drop glances: a page seen once for less than GLANCE_MIN isn't real work.
    pages.each do |title, p|
      next if p[:visits] == 1 && p[:dwell] < GLANCE_MIN

      mins = (p[:dwell] / 60.0).round
      tag  = "#{p[:visits]}x, #{mins}min"
      browser_entries << {
        ts: p[:ts],
        cmd: "#{title} (#{p[:host]}) [#{tag}]",
        source: "browser"
      }
    end

    File.delete(tmp_db) if File.exist?(tmp_db)
  end
end

puts "🌐  Found #{browser_entries.size} browser pages (after dropping glances)"

# ── Merge and sort all entries ────────────────────────────────────────────────
all_entries = (shell_entries + git_entries + browser_entries)
              .sort_by { |e| e[:ts] }.uniq { |e| e[:ts] }

if all_entries.empty?
  puts "\n😶  No activity found for #{date_label}."
  exit 0
end

# ── Estimate total active time (ignoring gaps > MAX_GAP min) ─────────────────
total_minutes = 0
all_entries.each_cons(2) do |a, b|
  gap = (b[:ts] - a[:ts]) / 60.0
  total_minutes += gap if gap <= MAX_GAP
end
total_minutes += 30 # buffer for last activity

puts ""

# ── Format history for Claude ─────────────────────────────────────────────────
history_text = all_entries.map do |e|
  time = Time.at(e[:ts]).strftime("%H:%M")
  src  = case e[:source]
         when "git"     then "[commit] "
         when "browser" then "[browser]"
         else "[shell]  "
         end
  "#{time}  #{src}  #{e[:cmd]}"
end.join("\n")

projects_list = PREFIX_TO_PROJECT.map { |prefix, project| "#{prefix}-XXXX => #{project}" }.join("\n")

prompt = <<~PROMPT
  You are helping log work hours into Noko time tracking for a software developer named Julio.

  Here is the activity for #{date_label} (shell commands + git commits + browser page visits):
  #{history_text}

  Total estimated active time: #{format_time(total_minutes)}
  Target workday: #{format_time(target_minutes)} total

  Known Noko project mappings (ticket prefix => project):
  #{projects_list.empty? ? "(none configured)" : projects_list}

  Here are real examples of how Julio logs time in Noko, so you can match his exact style:

  Examples:
  - 6:00 | Ombots | AUT-340 and AUT-339: Adding logging for manual roadmap
  - 4:00 | Ombots | AUT-341 Add logging to components/milestones/*
  - 0:30 | Operations | catch up with email and slack
  - 0:30 | Operations | #calls Standup
  - 1:00 | Fixers Guild | #calls Planning
  - 0:30 | Fixers Guild | Review Ays blog
  - 3:00 | Fixers Guild | AUT-324: Add roadmap generation tests
  - 0:30 | Fixers Guild | Review on AUT-344, AUT-343
  - 2:00 | Fixers Guild | AUT-324-add-git-roadmap-generation-tests

  Style rules:
  - Keep descriptions short and natural, like the examples above
  - Infer tickets from branch names (e.g. git checkout -b AUT-340-some-description => AUT-340)
  - Group same-ticket work into one entry when possible
  - If multiple tickets are related, combine them: "AUT-340 and AUT-339: description"
  - Tag calls with #calls at the start of the description
  - [browser] lines end with an engagement tag like [3x, 25min] = visits, time on page.
    Weight them by that: high visits/minutes means real work; a low tag (e.g. 1x, 3min)
    is likely just a page you glanced at (someone else's ticket, a link) — don't log it as work.
  - Ignore gaps > #{MAX_GAP} minutes (lunch/breaks)
  - Total time should add up exactly to #{format_time(target_minutes)}
  - Always include an Operations entry of at least 0:30 for standup/email if there's no other operations activity

  Return a JSON object with an "entries" array. Each entry:
  - "time": H:MM format
  - "project": Noko project name from the mappings
  - "description": short natural description in Julio's style
PROMPT

# ── Call Claude API ───────────────────────────────────────────────────────────
puts "🤖  Asking Claude to analyze your activity...\n\n"

uri = URI("https://api.anthropic.com/v1/messages")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Post.new(uri)
request["Content-Type"]      = "application/json"
request["x-api-key"]         = ENV["ANTHROPIC_API_KEY"]
request["anthropic-version"] = "2023-06-01"

request.body = JSON.generate({
  model: "claude-sonnet-4-6",
  max_tokens: 1000,
  output_config: {
    format: {
      type: "json_schema",
      schema: {
        type: "object",
        properties: {
          entries: {
            type: "array",
            items: {
              type: "object",
              properties: {
                time: { type: "string" },
                project: { type: "string" },
                description: { type: "string" }
              },
              required: ["time", "project", "description"],
              additionalProperties: false
            }
          }
        },
        required: ["entries"],
        additionalProperties: false
      }
    }
  },
  messages: [{ role: "user", content: prompt }]
})

response = http.request(request)
data = JSON.parse(response.body)

unless response.code == "200"
  abort "❌  API error: #{data["error"]&.dig("message") || response.body}"
end

raw = data.dig("content", 0, "text").to_s.strip

begin
  parsed = JSON.parse(raw)
rescue JSON::ParserError
  abort "❌  Could not parse Claude's response:\n#{raw}"
end

# Structured output returns { "entries": [...] }; tolerate a bare array too
entries_out = parsed.is_a?(Hash) ? parsed["entries"] : parsed

unless entries_out.is_a?(Array)
  abort "❌  Claude response did not contain an entries array"
end

parsed_minutes = entries_out.map { |e| parse_hmm_to_minutes(e["time"]) }
if parsed_minutes.any?(&:nil?)
  abort "❌  Claude returned invalid time format. Expected H:MM for every entry"
end

current_total = parsed_minutes.sum
diff = target_minutes - current_total

if diff != 0
  idx = parsed_minutes.each_with_index.max_by { |mins, _i| mins }&.last

  if idx.nil?
    entries_out << {
      "time" => format_time(target_minutes),
      "project" => "Operations",
      "description" => "General admin"
    }
  else
    adjusted = parsed_minutes[idx] + diff

    if adjusted < 0
      abort "❌  Could not adjust entries to match #{format_time(target_minutes)}"
    end

    entries_out[idx]["time"] = format_time(adjusted)
  end
end

# ── Output ────────────────────────────────────────────────────────────────────
puts "=" * 55
puts "  Noko Time Summary — #{date_label}"
puts "=" * 55
puts "  Target total time:    #{format_time(target_minutes)}"
puts "-" * 55

entries_out.each do |e|
  puts "\n  ⏱  #{e["time"]}"
  puts "  📁  #{e["project"] || "(no project match)"}"
  puts "  📝  #{e["description"]}"
end

puts "\n" + "=" * 55
puts "  Copy-paste format (TIME | PROJECT | DESCRIPTION):"
puts "-" * 55

entries_out.each do |e|
  puts "#{e["time"]} | #{e["project"] || "???"} | #{e["description"]}"
end

puts ""
