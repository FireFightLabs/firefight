module Integrations
  module Sandboxes
    # Boxes as Northflank services, each a microVM, reached over Northflank's private network. In the app's own project a
    # box is reached by its service id. In a project of their own, which allows ingress from the app's project, it is
    # reached by its service id and that project's namespace.
    class Northflank < Provider
      API_ROOT = "https://api.northflank.com/v1".freeze
      PORT = 8080
      DEFAULT_PLAN = "nf-compute-100-2".freeze
      # Megabytes. Repositories, their dependencies and a database for their tests share it.
      DEFAULT_STORAGE = 16_384
      DESCRIPTION = "Firefight code sandbox".freeze

      def start(name:, owner: nil, **)
        suffix = host_suffix
        key = SecureRandom.hex(32)
        created = request(Net::HTTP::Post, "/projects/#{project}/services/deployment", {
          name: name, description: owner ? "#{DESCRIPTION} for #{owner.text}" : DESCRIPTION,
          billing: { deploymentPlan: size },
          deployment: {
            instances: 1, docker: { configType: "default" }, external: { imagePath: Sandboxes.image },
            storage: { ephemeralStorage: { storageSize: Integer(ENV["NORTHFLANK_SANDBOX_STORAGE"].presence || DEFAULT_STORAGE) } }
          },
          ports: [ { name: "cmd", internalPort: PORT, public: false, protocol: "HTTP" } ],
          runtimeEnvironment: { SANDBOX_KEY: key }
        })
        ref = created.dig("data", "id")
        raise Error, "Northflank created no service." if ref.blank?

        Box.new(ref: ref, address: "http://#{ref}#{suffix}:#{PORT}", key: key)
      end

      # Northflank answers a service's variables only from its runtime environment
      # (docs/v1/api/services/get-service-runtime-environment).
      def reclaim(ref)
        key = request(Net::HTTP::Get, "/projects/#{project}/services/#{ref}/runtime-environment").dig("data", "runtimeEnvironment", "SANDBOX_KEY")
        raise Error, "Northflank holds no key for the code sandbox #{ref}." if key.blank?

        Box.new(ref: ref, address: "http://#{ref}#{host_suffix}:#{PORT}", key: key)
      end

      def stop(ref)
        request(Net::HTTP::Delete, "/projects/#{project}/services/#{ref}")
      rescue Error => error
        raise unless error.message.include?("404")
      end

      def running = boxes.map { |service| Running.new(ref: service["id"], started_at: Time.zone.parse(service["createdAt"].to_s)) }

      PHASES = { "PENDING" => ProviderSandbox::PHASE_STARTING, "IN_PROGRESS" => ProviderSandbox::PHASE_STARTING,
                 "COMPLETED" => ProviderSandbox::PHASE_RUNNING, "FAILED" => ProviderSandbox::PHASE_FAILED }.freeze

      # Northflank lists a service's deployment state under status.deployment.status (docs/v1/api/services/list-services).
      def inventory
        boxes.map do |service|
          state = service.dig("status", "deployment", "status")
          Held.new(kind: ProviderSandbox::KIND_BOX, ref: service["id"], name: service["name"], state: state, phase: PHASES[state],
                   size: size, started_at: (Time.zone.parse(service["createdAt"].to_s) if service["createdAt"]), owner: Owner.in(service["description"]))
        end
      end

      def size = ENV["NORTHFLANK_SANDBOX_PLAN"].presence || DEFAULT_PLAN

      # The plan's amountPerHour from Northflank's GET /v1/plans. A price that cannot be read leaves the box unpriced
      # rather than stopping it.
      def hourly_micros
        plan = request(Net::HTTP::Get, "/plans").dig("data", "plans").to_a.find { |each| each["id"] == size }
        plan && (plan["amountPerHour"].to_f * 1_000_000).round
      rescue Error => error
        Rails.logger.warn({ event: "code_box.price_unread", provider: SandboxProviders::NORTHFLANK, error: error.message }.to_json)
        nil
      end

      private

      # Only services named like a box, so the app's own services in a shared project are never listed.
      def boxes
        services = request(Net::HTTP::Get, "/projects/#{project}/services?per_page=100").dig("data", "services").to_a
        services.select { |service| service["name"].to_s.start_with?(NAME_PREFIX) }
      end

      def project = ENV["NORTHFLANK_SANDBOX_PROJECT"].presence || raise(Error, "NORTHFLANK_SANDBOX_PROJECT is not set.")

      # Northflank sets NF_PROJECT_ID in every deployment it runs (docs/v1/application/secure/inject-secrets). An app
      # that is not on Northflank has no project of its own, and keeps the address inside the boxes' project.
      def app_project = ENV["NF_PROJECT_ID"].presence

      # Read before a service is made, so a project that refuses the app's traffic refuses before anything starts.
      def host_suffix = separate_project? ? ".#{ingress_namespace}" : ""

      def separate_project? =app_project.present? && app_project != project

      # A port in a project that allows ingress from another gets an address for that traffic, shown as
      # <service id>.<namespace>:<port> (docs/v1/application/network/enable-multi-project-networking). The namespace is
      # the project's cluster.namespace (docs/v1/api/team/projects/get-project), known before any box exists, and
      # reachability is waited for like any box's. Northflank documents networking.allowedIngressProjects on writing a
      # project but not on reading one, so it is checked only when the answer carries it.
      def ingress_namespace
        details = request(Net::HTTP::Get, "/projects/#{project}")["data"].to_h
        allowed = details.dig("networking", "allowedIngressProjects")
        if allowed && !allowed.include?(app_project)
          raise Error, "Northflank project #{project} (NORTHFLANK_SANDBOX_PROJECT) does not allow ingress from #{app_project}, " \
                       "the app's project. Add #{app_project} to its ingress projects in the project's networking settings."
        end

        details.dig("cluster", "namespace").presence || raise(Error, "Northflank gave no namespace for project #{project}.")
      end

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
