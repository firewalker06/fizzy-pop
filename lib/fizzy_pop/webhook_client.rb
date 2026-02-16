module FizzyPop
  class WebhookClient
    def initialize(base_url, token)
      @base_url = base_url
      @token = token
      @headers = {
        "authorization" => "Bearer #{token}",
        "content-type" => "application/json"
      }
      @http = HTTPX.with(headers: @headers)
    end

    # Docs: https://docs.openclaw.ai/automation/webhook#post-/hooks/agent
    def deliver(agent_name, message)
      webhook_url = "#{@base_url}/hooks/agent"
      payload = JSON.generate(
        agentId: agent_name,
        message: message,
        mode: "now",
        deliver: false
      )

      if Debug.dry_run
        puts "\n--dry-run: would POST to #{webhook_url}"
        puts "Body: #{payload}"
        return
      end

      Debug.debug_request("POST", webhook_url, headers: @headers, body: payload)
      if Debug.handle_response(@http.post(webhook_url, body: payload), "Webhook")
        puts "\e[32m[#{agent_name}]\e[0m Webhook delivered successfully."
      end
    end
  end
end
