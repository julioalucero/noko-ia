module Noko
  # Talks to the Claude API: sends the prompt, parses the structured response,
  # and balances the entries so their times add up to the target workday.
  class Claude
    API_URL = "https://api.anthropic.com/v1/messages"
    MODEL   = "claude-sonnet-4-6"
    VERSION = "2023-06-01"

    def initialize(api_key)
      @api_key = api_key
    end

    # Returns an array of entry hashes: { "time", "project", "description" }.
    def analyze(prompt, target_minutes:)
      balance(request(prompt), target_minutes)
    end

    private

    def request(prompt)
      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"]      = "application/json"
      req["x-api-key"]         = @api_key
      req["anthropic-version"] = VERSION
      req.body = JSON.generate(payload(prompt))

      response = http.request(req)
      data = JSON.parse(response.body)
      unless response.code == "200"
        abort "❌  API error: #{data["error"]&.dig("message") || response.body}"
      end

      parse_entries(data)
    end

    def payload(prompt)
      {
        model: MODEL,
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
      }
    end

    def parse_entries(data)
      raw = data.dig("content", 0, "text").to_s.strip

      parsed = begin
        JSON.parse(raw)
      rescue JSON::ParserError
        abort "❌  Could not parse Claude's response:\n#{raw}"
      end

      # Structured output returns { "entries": [...] }; tolerate a bare array.
      entries = parsed.is_a?(Hash) ? parsed["entries"] : parsed
      abort "❌  Claude response did not contain an entries array" unless entries.is_a?(Array)

      entries
    end

    # Nudge the largest entry so the times sum exactly to the target.
    def balance(entries, target_minutes)
      minutes = entries.map { |e| TimeFormat.parse(e["time"]) }
      if minutes.any?(&:nil?)
        abort "❌  Claude returned invalid time format. Expected H:MM for every entry"
      end

      diff = target_minutes - minutes.sum
      return entries if diff.zero?

      idx = minutes.each_with_index.max_by { |mins, _i| mins }&.last

      if idx.nil?
        entries << {
          "time" => TimeFormat.format(target_minutes),
          "project" => "Operations",
          "description" => "General admin"
        }
      else
        adjusted = minutes[idx] + diff
        if adjusted.negative?
          abort "❌  Could not adjust entries to match #{TimeFormat.format(target_minutes)}"
        end
        entries[idx]["time"] = TimeFormat.format(adjusted)
      end

      entries
    end
  end
end
