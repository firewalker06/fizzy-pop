module FizzyPop
  class Config
    DEFAULT_INTERVAL_POLLING = 10
    DEFAULT_INTERVAL_WEBHOOK = 3
    DEFAULT_INTERVAL_AGENT_POLL = 0.5

    attr_reader :url, :webhook_url, :webhook_token, :interval_polling, :interval_webhook, :interval_agent_poll, :dry_run, :verbose, :agents

    def initialize(argv)
      options = { agents: [] }

      OptionParser.new do |opts|
        opts.banner = "Usage: fizzy-pop [--config FILE | --token TOKEN] [options]"

        opts.on("--url URL", "Fizzy base URL (e.g. https://app.fizzy.do)") { |v| options[:url] = v }
        opts.on("--token TOKEN", "Fizzy personal access token (single agent mode)") { |v| options[:token] = v }
        opts.on("--config FILE", "YAML config file for multi-agent mode") { |v| options[:config] = v }
        opts.on("--webhook-url URL", "OpenClaw webhook base URL") { |v| options[:webhook_url] = v }
        opts.on("--webhook-token TOKEN", "OpenClaw webhook token") { |v| options[:webhook_token] = v }
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

        if config["polling"]
          warn "\e[33m[warning]\e[0m 'polling' is deprecated. Use 'interval' instead. Defaulting to interval.polling: #{DEFAULT_INTERVAL_POLLING}s, interval.webhook: #{DEFAULT_INTERVAL_WEBHOOK}s, interval.agent_poll: #{DEFAULT_INTERVAL_AGENT_POLL}s"
        end

        if config["interval"].is_a?(Hash)
          options[:interval_polling] = config["interval"]["polling"]
          options[:interval_webhook] = config["interval"]["webhook"]
          options[:interval_agent_poll] = config["interval"]["agent_poll"]
        end

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
      @interval_polling = options[:interval_polling] || DEFAULT_INTERVAL_POLLING
      @interval_webhook = options[:interval_webhook] || DEFAULT_INTERVAL_WEBHOOK
      @interval_agent_poll = options[:interval_agent_poll] || DEFAULT_INTERVAL_AGENT_POLL
      @dry_run = options[:dry_run]
      @verbose = options[:verbose]
      @agents = options[:agents]
    end
  end
end
