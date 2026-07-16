module Noko
  # Loads .env into ENV and reads noko_projects.yml (project mappings +
  # browser domains). All paths are relative to the project root.
  class Config
    ENV_FILE    = File.join(ROOT, ".env")
    CONFIG_FILE = File.join(ROOT, "noko_projects.yml")

    attr_reader :prefix_to_project, :browser_domains

    def initialize
      @prefix_to_project = {}
      @browser_domains = []
      load_env
      load_projects
    end

    def api_key
      ENV["ANTHROPIC_API_KEY"]
    end

    def github_token
      ENV["GITHUB_TOKEN"]
    end

    private

    def load_env
      return unless File.exist?(ENV_FILE)

      File.readlines(ENV_FILE).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        key, value = line.split("=", 2)
        ENV[key.strip] = value.strip if key && value
      end
    end

    def load_projects
      unless File.exist?(CONFIG_FILE)
        warn "⚠️  Config file not found: #{CONFIG_FILE}"
        return
      end

      config = YAML.load_file(CONFIG_FILE)
      (config["projects"] || {}).each do |project, prefix|
        @prefix_to_project[prefix.upcase] = project if prefix
      end
      @browser_domains.concat(Array(config["browser_domains"]).compact.map(&:to_s))
    end
  end
end
