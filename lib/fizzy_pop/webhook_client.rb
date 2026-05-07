module FizzyPop
  class WebhookClient
    def initialize(base_url, token, adapter:)
      @base_url = base_url
      @token = token
      @adapter = adapter
      @http = HTTPX
    end

    def deliver(agent_name, message)
      webhook_url = @adapter.url(@base_url)
      payload = @adapter.payload(agent_name, message)
      headers = @adapter.headers(@token, payload)

      if Debug.dry_run
        puts "\n--dry-run: would POST to #{webhook_url}"
        puts "Body: #{payload}"
        return
      end

      Debug.debug_request("POST", webhook_url, headers: headers, body: payload)
      if Debug.handle_response(@http.post(webhook_url, headers: headers, body: payload), @adapter.label)
        puts "\e[32m[#{agent_name}]\e[0m Webhook delivered successfully."
      end
    end
  end
end
