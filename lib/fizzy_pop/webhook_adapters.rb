module FizzyPop
  module WebhookAdapters
    def self.build(name, route: nil)
      case name
      when "openclaw"
        OpenClaw.new
      when "hermes"
        Hermes.new(route: route)
      else
        raise ArgumentError, "Unknown webhook adapter: #{name}"
      end
    end

    class OpenClaw
      def url(base_url)
        "#{base_url}/hooks/agent"
      end

      def payload(agent_name, message)
        JSON.generate(
          agentId: agent_name,
          message: message,
          mode: "now",
          deliver: false
        )
      end

      def headers(token, _payload)
        {
          "authorization" => "Bearer #{token}",
          "content-type" => "application/json"
        }
      end

      def label
        "OpenClaw webhook"
      end
    end

    class Hermes
      DEFAULT_ROUTE = "fizzy"

      def initialize(route: nil)
        @route = normalize_route(route)
      end

      def url(base_url)
        "#{base_url}/webhooks/#{@route}"
      end

      def payload(agent_name, message)
        JSON.generate(
          event_type: "fizzy_notification",
          agent: agent_name,
          message: message
        )
      end

      def headers(token, payload)
        {
          "content-type" => "application/json",
          "x-webhook-signature" => OpenSSL::HMAC.hexdigest("SHA256", token, payload),
          "x-request-id" => "fizzy-pop-#{Digest::SHA256.hexdigest(payload)[0, 32]}"
        }
      end

      def label
        "Hermes webhook"
      end

      private

      def normalize_route(route)
        value = route.to_s.strip
        value = DEFAULT_ROUTE if value.empty?
        value = value.sub(%r{\A/+}, "")
        value.sub(%r{\Awebhooks/+}, "")
      end
    end
  end
end
