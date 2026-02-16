module FizzyPop
  class FizzyClient
    def initialize(base_url, token)
      @base_url = base_url
      headers = {
        "authorization" => "Bearer #{token}",
        "accept" => "application/json",
        "content-type" => "application/json"
      }
      @http = HTTPX.with(headers: headers)
    end

    def identity
      url = "#{@base_url}/my/identity"
      Debug.debug_request("GET", url, headers: { "authorization" => "[REDACTED]" })
      response = Debug.handle_response(@http.get(url), "Identity")
      return nil unless response

      JSON.parse(response.body.to_s)
    end

    def notifications(slug)
      url = "#{@base_url}#{slug}/notifications"
      Debug.debug_request("GET", url, headers: { "authorization" => "[REDACTED]" })
      response = Debug.handle_response(@http.get(url), "Notifications")
      return nil unless response

      JSON.parse(response.body.to_s)
    end

    def mark_read(slug, notification_id)
      url = "#{@base_url}#{slug}/notifications/#{notification_id}/reading"
      Debug.debug_request("POST", url, headers: { "authorization" => "[REDACTED]" })
      Debug.handle_response(@http.post(url), "Mark read")
    end
  end
end
