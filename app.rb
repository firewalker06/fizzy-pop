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
end.parse!

abort "Missing required --url" unless options[:url]
abort "Missing required --token" unless options[:token]

BASE_URL = options[:url]
FIZZY_TOKEN = options[:token]
WEBHOOK_BASE_URL = options[:webhook_url]
WEBHOOK_TOKEN = options[:webhook_token]
POLLING_DURATION = options[:polling]
DRY_RUN = options[:dry_run]

def handle_response(response, label)
  if response.is_a?(HTTPX::ErrorResponse)
    puts "#{label} error: #{response.error.message}"
    nil
  elsif (200..299).cover?(response.status.to_i)
    response
  else
    puts "#{label} failed (HTTP #{response.status}): #{response.body}"
    nil
  end
end

fizzy_http_client = HTTPX.with(
  headers: {
    "authorization" => "Bearer #{FIZZY_TOKEN}",
    "accept" => "application/json",
    "content-type" => "application/json"
  }
)

webhook_http_client = HTTPX.with(
  headers: {
    "authorization" => "Bearer #{WEBHOOK_TOKEN}",
    "content-type" => "application/json"
  }
) if WEBHOOK_TOKEN

# First, get the account slug from identity
breadcrumbs << "get_identity"
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
        handle_response(fizzy_http_client.post("#{BASE_URL}#{slug}/notifications/#{unread["id"]}/reading"), "Mark read")
        puts "Marked notification #{unread["id"]} as read."
      end

      next if unread["creator"].nil? # Only process comment and mention notifications

      message = <<~PROMPT
                The following is notification from Fizzy:
                From: #{unread["creator"]["name"]} (#{unread["creator"]["id"]})
                Title: #{unread["title"]}
                Message: #{unread["body"]}

                Send 👀 reaction (boost) to #{unread["card"]["url"]}, which means you have read this.
                If the message contains instruction for you, follow up by replying there and then do the action required.
                DO NOTHING if no action is needed.
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
