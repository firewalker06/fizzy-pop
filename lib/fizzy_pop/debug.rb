module FizzyPop
  module Debug
    @verbose = false
    @dry_run = false
    @breadcrumbs = ["begin"]

    class << self
      attr_accessor :verbose, :dry_run
      attr_reader :breadcrumbs

      def reset_breadcrumbs
        @breadcrumbs.replace(["begin"])
      end

      def debug_request(method, url, headers: {}, body: nil)
        puts "\e[36m--> #{method.upcase} #{url}\e[0m"
        if @verbose
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
          if @verbose
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
    end
  end
end
