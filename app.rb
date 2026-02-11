$stdout.sync = true

require "httpx"
require "json"
require "optparse"

options = { polling: 10 }
breadcrumbs = ["begin"]

OptionParser.new do |opts|
  opts.banner = "Usage: ruby app.rb --url URL --token TOKEN [options]"

  opts.on("--url URL", "Fizzy base URL (e.g. https://app.fizzy.do)") { |v| options[:url] = v }
  opts.on("--token TOKEN", "Fizzy personal access token") { |v| options[:token] = v }
  opts.on("--webhook-url URL", "OpenClaw webhook base URL") { |v| options[:webhook_url] = v }
  opts.on("--webhook-token TOKEN", "OpenClaw webhook token") { |v| options[:webhook_token] = v }
  opts.on("--polling SECONDS", Integer, "Polling interval in seconds (default: 10)") { |v| options[:polling] = v }
  opts.on("--dry-run", "Print webhook requests instead of sending them") { options[:dry_run] = true }
  opts.on("--verbose", "Print full request/response headers and body") { options[:verbose] = true }
end.parse!

abort "Missing required --url" unless options[:url]
abort "Missing required --token" unless options[:token]

BASE_URL = options[:url]
FIZZY_TOKEN = options[:token]
WEBHOOK_BASE_URL = options[:webhook_url]
WEBHOOK_TOKEN = options[:webhook_token]
POLLING_DURATION = options[:polling]
DRY_RUN = options[:dry_run]
VERBOSE = options[:verbose]

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

FIZZY_HEADERS = {
  "authorization" => "Bearer #{FIZZY_TOKEN}",
  "accept" => "application/json",
  "content-type" => "application/json"
}

WEBHOOK_HEADERS = {
  "authorization" => "Bearer #{WEBHOOK_TOKEN}",
  "content-type" => "application/json"
}

fizzy_http_client = HTTPX.with(headers: FIZZY_HEADERS)
webhook_http_client = HTTPX.with(headers: WEBHOOK_HEADERS) if WEBHOOK_TOKEN

# First, get the account slug from identity
breadcrumbs << "get_identity"
debug_request("GET", "#{BASE_URL}/my/identity", headers: FIZZY_HEADERS)
response = handle_response(fizzy_http_client.get("#{BASE_URL}/my/identity"), "Identity")
abort "Failed to fetch identity" unless response

identity = JSON.parse(response.body.to_s)
accounts = identity["accounts"]

if accounts.nil? || accounts.empty?
  abort "No accounts found for this token."
end

puts "Polling for notifications every #{POLLING_DURATION} seconds... (Ctrl+C to stop)"

begin
  loop do
    accounts.each do |account|
      slug = account["slug"]
      user = account["user"]

      breadcrumbs << "get_notifications"
      debug_request("GET", "#{BASE_URL}#{slug}/notifications", headers: FIZZY_HEADERS)
      response = handle_response(fizzy_http_client.get("#{BASE_URL}#{slug}/notifications"), "Notifications")
      next unless response

      notifications = JSON.parse(response.body.to_s)
      unread = notifications.select { |n| !n["read"] }.first

      if unread.nil?
        next
      elsif DRY_RUN
        puts "Will mark notification #{unread["id"]} as read."
      else
        breadcrumbs << "read_notification"
        mark_read_url = "#{BASE_URL}#{slug}/notifications/#{unread["id"]}/reading"
        debug_request("POST", mark_read_url, headers: FIZZY_HEADERS)
        handle_response(fizzy_http_client.post(mark_read_url), "Mark read")
        puts "Marked notification #{unread["id"]} as read."
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

      puts message

      breadcrumbs << "send_webhook"
      # Send to OpenClaw webhook
      webhook_url = "#{WEBHOOK_BASE_URL}/hooks/agent"
      payload = JSON.generate(message: message, mode: "now", deliver: false)
      if DRY_RUN
        puts "\n--dry-run: would POST to #{webhook_url}"
        puts "Body: #{payload}"
      else
        if WEBHOOK_BASE_URL.nil? || webhook_http_client.nil?
          abort "Missing required --webhook-url and --webhook-token"
        end

        debug_request("POST", webhook_url, headers: WEBHOOK_HEADERS, body: payload)
        if handle_response(webhook_http_client.post(webhook_url, body: payload), "Webhook")
          puts "Webhook delivered successfully."
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
