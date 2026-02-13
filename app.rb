$stdout.sync = true

require "httpx"
require "json"
require "optparse"
require "yaml"

options = { polling: 10, agents: [] }
breadcrumbs = ["begin"]

OptionParser.new do |opts|
  opts.banner = "Usage: ruby app.rb [--config FILE | --token TOKEN] [options]"

  opts.on("--url URL", "Fizzy base URL (e.g. https://app.fizzy.do)") { |v| options[:url] = v }
  opts.on("--token TOKEN", "Fizzy personal access token (single agent mode)") { |v| options[:token] = v }
  opts.on("--config FILE", "YAML config file for multi-agent mode") { |v| options[:config] = v }
  opts.on("--webhook-url URL", "OpenClaw webhook base URL") { |v| options[:webhook_url] = v }
  opts.on("--webhook-token TOKEN", "OpenClaw webhook token") { |v| options[:webhook_token] = v }
  opts.on("--polling SECONDS", Integer, "Polling interval in seconds (default: 10)") { |v| options[:polling] = v }
  opts.on("--dry-run", "Print webhook requests instead of sending them") { options[:dry_run] = true }
  opts.on("--verbose", "Print full request/response headers and body") { options[:verbose] = true }
end.parse!

# Load config file if provided
if options[:config]
  unless File.exist?(options[:config])
    abort "Config file not found: #{options[:config]}"
  end

  config = YAML.safe_load(File.read(options[:config]), permitted_classes: [], permitted_symbols: [], aliases: false)

  # Override options from config (CLI flags take precedence)
  options[:url] ||= config["url"]
  options[:webhook_url] ||= config["webhook_url"]
  options[:webhook_token] ||= config["webhook_token"]
  options[:polling] = config["polling"] if config["polling"] && options[:polling] == 10

  # Load agents from config
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

BASE_URL = options[:url]
WEBHOOK_BASE_URL = options[:webhook_url]
WEBHOOK_TOKEN = options[:webhook_token]
POLLING_DURATION = options[:polling]
DRY_RUN = options[:dry_run]
VERBOSE = options[:verbose]
AGENTS = options[:agents]

def debug_request(method, url, headers: {}, body: nil)
  puts "\e[36m--> #{method.upcase} #{url}\e[0m"
  if VERBOSE
    headers.each { |k, v| puts "\e[36m    #{k}: #{k.downcase == "authorization" ? "[REDACTED]" : v}\e[0m" }
    if body
      puts "\e[36m    Body:\e[0m"
      puts "\e[31m      #{body}\e[0m"
    end
  end
end

def debug_response(response, label)
  if response.is_a?(HTTPX::ErrorResponse)
    puts "\e[31m<-- #{label} error: #{response.error.message}\e[0m"
    puts "\e[31m    #{response.body.inspect}\e[0m" if response.body
  else
    status = response.status.to_i
    color = (200..299).cover?(status) ? "\e[32m" : "\e[31m"
    puts "#{color}<-- #{label} #{status} (#{response.body.to_s.bytesize} bytes)\e[0m"
    if VERBOSE
      response.headers.each { |k, v| puts "#{color}    #{k}: #{v}\e[0m" }
      body = response.body.to_s
      unless body.empty?
        puts "#{color}    Body:\e[0m"
        puts "#{color}#{JSON.pretty_generate(JSON.parse(body.to_s)).gsub(/^/, " " * 6)}\e[0m"
      end
    end
  end
end

def handle_response(response, label)
  debug_response(response, label)
  if response.is_a?(HTTPX::ErrorResponse)
    nil
  elsif (200..299).cover?(response.status.to_i)
    response
  else
    nil
  end
end

WEBHOOK_HEADERS = {
  "authorization" => "Bearer #{WEBHOOK_TOKEN}",
  "content-type" => "application/json"
}

webhook_http_client = HTTPX.with(headers: WEBHOOK_HEADERS) if WEBHOOK_TOKEN

# Build agent clients
agent_clients = AGENTS.map do |agent|
  headers = {
    "authorization" => "Bearer #{agent[:token]}",
    "accept" => "application/json",
    "content-type" => "application/json"
  }
  {
    name: agent[:name],
    token: agent[:token],
    http: HTTPX.with(headers: headers),
    accounts: nil
  }
end

# Fetch identity for each agent
agent_clients.each do |agent|
  breadcrumbs << "get_identity:#{agent[:name]}"
  puts "\e[33m[#{agent[:name]}]\e[0m Fetching identity..."
  debug_request("GET", "#{BASE_URL}/my/identity", headers: { "authorization" => "[REDACTED]" })
  response = handle_response(agent[:http].get("#{BASE_URL}/my/identity"), "Identity")

  if response
    identity = JSON.parse(response.body.to_s)
    agent[:accounts] = identity["accounts"]
    puts "\e[32m[#{agent[:name]}]\e[0m Found #{agent[:accounts]&.length || 0} account(s)"
  else
    puts "\e[31m[#{agent[:name]}]\e[0m Failed to fetch identity"
    agent[:accounts] = []
  end
end

# Remove agents with no accounts
active_agents = agent_clients.select { |a| a[:accounts] && !a[:accounts].empty? }
if active_agents.empty?
  abort "No agents have valid accounts. Check your tokens."
end

puts "Polling #{active_agents.length} agent(s) for notifications every #{POLLING_DURATION} seconds... (Ctrl+C to stop)"

begin
  loop do
    active_agents.each do |agent|
      agent[:accounts].each do |account|
        slug = account["slug"]

        breadcrumbs << "get_notifications:#{agent[:name]}"
        debug_request("GET", "#{BASE_URL}#{slug}/notifications", headers: { "authorization" => "[REDACTED]" })
        response = handle_response(agent[:http].get("#{BASE_URL}#{slug}/notifications"), "Notifications")
        next unless response

        notifications = JSON.parse(response.body.to_s)
        unread = notifications.select { |n| !n["read"] }.first

        if unread.nil?
          next
        elsif DRY_RUN
          puts "\e[33m[#{agent[:name]}]\e[0m Will mark notification #{unread["id"]} as read."
        else
          breadcrumbs << "read_notification:#{agent[:name]}"
          mark_read_url = "#{BASE_URL}#{slug}/notifications/#{unread["id"]}/reading"
          debug_request("POST", mark_read_url, headers: { "authorization" => "[REDACTED]" })
          handle_response(agent[:http].post(mark_read_url), "Mark read")
          puts "\e[33m[#{agent[:name]}]\e[0m Marked notification #{unread["id"]} as read."
        end

        next if unread["creator"].nil? # Only process comment and mention notifications

        message = <<~PROMPT
                  You have a new notification in Fizzy that requires your attention.

                  # Fizzy command check
                  DO NOTHING if fizzy is not available in shell.

                  # Task
                  - Read the Card from the notification.
                  - Read the latest comment on the card.
                  - Check whether the card already have 👀 reaction (boost) from you.
                    - Send 👀 boost to the card URL provided ONLY WHEN there is no boost from you
                  - DO THE INSTRUCTION in the latest comment if any instruction is provided.
                  - DO NOTHING if there is no action.

                  # Notification details
                  From: #{unread["creator"]["name"]} (#{unread["creator"]["id"]})
                  Title: #{unread["title"]}
                  Message: #{unread["body"]}
                  Card: #{unread["card"]["url"].split("/").last}

                  # Commands Reference
                  fizzy reaction list --card NUMBER
                  fizzy reaction create --card NUMBER --content "emoji"
                  fizzy reaction delete REACTION_ID --card NUMBER
                  fizzy reaction list --card NUMBER --comment COMMENT_ID
                  fizzy reaction create --card NUMBER --comment COMMENT_ID --content "emoji"
                  fizzy reaction delete REACTION_ID --card NUMBER --comment COMMENT_ID
                  fizzy comment list --card NUMBER [--page N] [--all]
                  fizzy comment show COMMENT_ID --card NUMBER
                  fizzy comment create --card NUMBER --body "HTML" [--body_file PATH] [--created-at TIMESTAMP]
                  fizzy comment update COMMENT_ID --card NUMBER [--body "HTML"] [--body_file PATH]
                  fizzy comment delete COMMENT_ID --card NUMBER
                  fizzy card column CARD_NUMBER --column ID     # Move to column (use column ID or: maybe, not-yet, done)
                  fizzy card move CARD_NUMBER --to BOARD_ID     # Move card to a different board
                  fizzy card assign CARD_NUMBER --user ID       # Toggle user assignment
                  fizzy card tag CARD_NUMBER --tag "name"       # Toggle tag (creates tag if needed)
                  fizzy card watch CARD_NUMBER                  # Subscribe to notifications
                  fizzy card unwatch CARD_NUMBER                # Unsubscribe
                  fizzy card pin CARD_NUMBER                    # Pin card for quick access
                  fizzy card unpin CARD_NUMBER                  # Unpin card
                  fizzy card golden CARD_NUMBER                 # Mark as golden/starred
                  fizzy card ungolden CARD_NUMBER               # Remove golden status
                  fizzy card image-remove CARD_NUMBER           # Remove header image
                PROMPT

        puts "\e[33m[#{agent[:name]}]\e[0m #{message}"

        breadcrumbs << "send_webhook:#{agent[:name]}"
        # Send to OpenClaw webhook with agent identifier
        webhook_url = "#{WEBHOOK_BASE_URL}/hooks/agent"
        payload = JSON.generate(
          agentId: agent[:name],
          message: message,
          mode: "now",
          deliver: false
        )

        if DRY_RUN
          puts "\n--dry-run: would POST to #{webhook_url}"
          puts "Body: #{payload}"
        else
          if WEBHOOK_BASE_URL.nil? || webhook_http_client.nil?
            abort "Missing required --webhook-url and --webhook-token"
          end

          debug_request("POST", webhook_url, headers: WEBHOOK_HEADERS, body: payload)
          if handle_response(webhook_http_client.post(webhook_url, body: payload), "Webhook")
            puts "\e[32m[#{agent[:name]}]\e[0m Webhook delivered successfully."
          end
        end
      end
    end

    breadcrumbs.replace(["begin"])
    sleep POLLING_DURATION
  end
rescue Interrupt, SignalException
  puts "\nBreadcrumbs: #{breadcrumbs.join(" -> ")}"
  puts "\nShutting down..."
rescue StandardError => e
  puts "\nBreadcrumbs: #{breadcrumbs.join(" -> ")}"
  puts "\nAn error occurred: #{e.message}"
end
