module Integrations
  module Sandboxes
    # Boxes as Northflank services in the app's own project, reached over its private network. Each is a microVM.
    class Northflank
      API_ROOT = "https://api.northflank.com/v1".freeze
      PORT = 8080
      DEFAULT_PLAN = "nf-compute-100-2".freeze
      # Megabytes. Repositories, their dependencies and a database for their tests share it.
      DEFAULT_STORAGE = 16_384

      def start(name:)
        key = SecureRandom.hex(32)
        created = request(Net::HTTP::Post, "/projects/#{project}/services/deployment", {
          name: name, description: "Firefight code sandbox",
          billing: { deploymentPlan: ENV["NORTHFLANK_SANDBOX_PLAN"].presence || DEFAULT_PLAN },
          deployment: {
            instances: 1, docker: { configType: "default" }, external: { imagePath: Sandboxes.image },
            storage: { ephemeralStorage: { storageSize: Integer(ENV["NORTHFLANK_SANDBOX_STORAGE"].presence || DEFAULT_STORAGE) } }
          },
          ports: [ { name: "cmd", internalPort: PORT, public: false, protocol: "HTTP" } ],
          runtimeEnvironment: { SANDBOX_KEY: key }
        })
        ref = created.dig("data", "id")
        raise Error, "Northflank created no service." if ref.blank?

        Box.new(ref: ref, address: "http://#{ref}:#{PORT}", key: key)
      end

      def stop(ref)
        request(Net::HTTP::Delete, "/projects/#{project}/services/#{ref}")
      rescue Error => error
        raise unless error.message.include?("404")
      end

      def running
        services = request(Net::HTTP::Get, "/projects/#{project}/services?per_page=100").dig("data", "services").to_a
        services.filter_map do |service|
          next unless service["name"].to_s.start_with?(NAME_PREFIX)

          Running.new(ref: service["id"], started_at: Time.zone.parse(service["createdAt"].to_s))
        end
      end

      private

      def project = ENV["NORTHFLANK_SANDBOX_PROJECT"].presence || raise(Error, "NORTHFLANK_SANDBOX_PROJECT is not set.")

      def token = ENV["NORTHFLANK_API_TOKEN"].presence || raise(Error, "NORTHFLANK_API_TOKEN is not set.")

      def request(verb, path, payload = nil)
        uri = URI.parse("#{API_ROOT}#{path}")
        http_request = verb.new(uri)
        http_request["Authorization"] = "Bearer #{token}"
        if payload
          http_request["Content-Type"] = "application/json"
          http_request.body = payload.to_json
        end
        response = Http.request(uri, http_request, error_class: Error, read_timeout: 60)
        body = response.body.to_s.empty? ? {} : JSON.parse(response.body)
        unless response.code.to_i.between?(200, 299)
          raise Error, "Northflank #{response.code}: #{body.dig('error', 'message') || body['message']}"
        end

        body
      rescue JSON::ParserError
        raise Error, "Northflank answered with something that is not JSON (HTTP #{response&.code})."
      end
    end
  end
end
