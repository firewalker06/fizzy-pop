module FizzyPop
  class Config
    attr_reader :url, :webhook_url, :webhook_token, :polling, :dry_run, :verbose, :agents

    def initialize(argv)
      options = { polling: 10, agents: [] }

      OptionParser.new do |opts|
        opts.banner = "Usage: fizzy-pop [--config FILE | --token TOKEN] [options]"

        opts.on("--url URL", "Fizzy base URL (e.g. https://app.fizzy.do)") { |v| options[:url] = v }
        opts.on("--token TOKEN", "Fizzy personal access token (single agent mode)") { |v| options[:token] = v }
        opts.on("--config FILE", "YAML config file for multi-agent mode") { |v| options[:config] = v }
        opts.on("--webhook-url URL", "OpenClaw webhook base URL") { |v| options[:webhook_url] = v }
        opts.on("--webhook-token TOKEN", "OpenClaw webhook token") { |v| options[:webhook_token] = v }
        opts.on("--polling SECONDS", Integer, "Polling interval in seconds (default: 10)") { |v| options[:polling] = v }
        opts.on("--dry-run", "Print webhook requests instead of sending them") { options[:dry_run] = true }
        opts.on("--verbose", "Print full request/response headers and body") { options[:verbose] = true }
      end.parse!(argv)

      if options[:config]
        unless File.exist?(options[:config])
          abort "Config file not found: #{options[:config]}"
        end

        config = YAML.safe_load(File.read(options[:config]), permitted_classes: [], permitted_symbols: [], aliases: false)

        options[:url] ||= config["url"]
        options[:webhook_url] ||= config["webhook_url"]
        options[:webhook_token] ||= config["webhook_token"]
        options[:polling] = config["polling"] if config["polling"] && options[:polling] == 10

        if config["agents"]
          options[:agents] = config["agents"].map do |agent|
            { name: agent["name"], token: agent["token"] }
          end
        end
      end

      # Backward compatibility: single --token creates a "default" agent
      if options[:token] && options[:agents].empty?
        options[:agents] = [{ name: "default", token: options[:token] }]
      end

      abort "Missing required --url" unless options[:url]
      abort "No agents configured. Use --token or --config with agents list" if options[:agents].empty?

      @url = options[:url]
      @webhook_url = options[:webhook_url]
      @webhook_token = options[:webhook_token]
      @polling = options[:polling]
      @dry_run = options[:dry_run]
      @verbose = options[:verbose]
      @agents = options[:agents]
    end
  end
end
