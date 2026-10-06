module Integrations
  module MapEventSources
    # Supabase's changes, sent by its Platform Webhooks to an endpoint an admin creates with the Management API, since
    # Firefight reaches Supabase through its MCP server and so cannot create one itself. Platform Webhooks are in early
    # access, and Supabase answers 403 access_disabled to an organization outside its allowlist
    # (supabase.com/docs/guides/platform/webhooks). The admin chooses the endpoint's signing secret and saves the same one
    # here. Each delivery is signed as Standard Webhooks specifies (Verify webhook signature), and its payload names the
    # organization and the project it is about (Envelope and payload), which the map reads again.
    class Supabase < MapEventSource
      ID_HEADER = "webhook-id".freeze
      TIMESTAMP_HEADER = "webhook-timestamp".freeze
      SIGNATURE_HEADER = "webhook-signature".freeze
      # Each signature is a version and a base64 HMAC-SHA256 of "<id>.<timestamp>.<body>". A secret written whsec_<base64>
      # is that key base64 encoded, and any other is the key as it is (Verify webhook signature, Base64 secret and Plain
      # string secret).
      SIGNATURE_VERSION = "v1".freeze
      SECRET_PREFIX = "whsec_".freeze
      # A delivery signed further from now than this is refused, the window the standardwebhooks library allows.
      TOLERANCE = 5.minutes

      # The project events that change what the map shows of a project or its branches, from the catalog
      # (supabase.com/docs/guides/platform/webhooks/events, Project events). A branch is a project of its own under its
      # parent, which the map reads with the parent. A branch removed, or a project moved to another organization, is
      # read in a full sweep, since only reading every project says where it is now.
      PROJECT_CREATED = "v1.project.created".freeze
      PROJECT_EVENTS = [ PROJECT_CREATED, "v1.project.paused", "v1.project.restored", "v1.project.restarted", "v1.project.removed", "v1.project.status.changed" ].freeze
      BRANCH_EVENTS = %w[v1.project.branch.created v1.project.branch.updated].freeze
      RESCOPE_EVENTS = %w[v1.project.branch.removed v1.project.transferred].freeze
      EVENTS = (PROJECT_EVENTS + BRANCH_EVENTS + RESCOPE_EVENTS).freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          id = headers[ID_HEADER].to_s
          stamp = headers[TIMESTAMP_HEADER].to_s
          return false if secret.blank? || id.empty? || !stamp.match?(/\A\d+\z/)
          return false if (Time.current.to_i - stamp.to_i).abs > TOLERANCE

          expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key_of(secret.to_s), "#{id}.#{stamp}.#{raw_body}"))
          headers[SIGNATURE_HEADER].to_s.split.any? do |entry|
            version, signature = entry.split(",", 2)
            version == SIGNATURE_VERSION && signature.present? && ActiveSupport::SecurityUtils.secure_compare(signature, expected)
          end
        end

        # One event for the project it names. Its id is the same for every retry (Idempotency and ordering), so a second
        # delivery is a no-op. A test event changes nothing.
        def events(payload, headers:)
          type = payload["type"].to_s
          body = payload["payload"].is_a?(Hash) ? payload["payload"] : {}
          project = body["project_ref"].presence
          return [] unless EVENTS.include?(type) && project && !body["is_test"]

          at = happened_at(payload["timestamp"])
          id = payload["id"].presence || headers[ID_HEADER]
          return [ ResourceMap::Event.new(id: id, at: at, action: ResourceMap::Event::RESCOPE) ] if RESCOPE_EVENTS.include?(type)

          scope = ResourceMap::Scope.new(account: body["organization_slug"], kind: ResourceMap::KIND_DATABASE, external_id: project)
          [ ResourceMap::Event.new(id: id, at: at, action: type == PROJECT_CREATED ? ResourceMap::Event::ADDED : ResourceMap::Event::UPDATED, scope: scope) ]
        end

        def limits = "Supabase says when a project or a preview branch changes in the organizations and projects you set an endpoint " \
                     "up for. Any other reaches the map at each hourly sweep."

        def setup_steps
          [
            "Choose a signing secret of 8 to 64 characters.",
            "Create a webhook endpoint with Supabase's Management API and a personal access token: POST " \
            "https://api.supabase.com/v2/organizations/<organization slug>/webhooks/endpoints for every project in an " \
            "organization, or /v2/projects/<project ref>/webhooks/endpoints for one project.",
            "Give it the address above as its url, the signing secret, and these event types: #{EVENTS.join(', ')}.",
            "Do the same for each organization this connection reaches, with the same signing secret, then save it below."
          ]
        end

        def by_hand_note
          "Supabase sends changes only to organizations in its Platform Webhooks early access, and answers any other with " \
            "access_disabled, so until then the map updates at each hourly sweep."
        end

        private

        def key_of(secret) = secret.start_with?(SECRET_PREFIX) ? Base64.decode64(secret.delete_prefix(SECRET_PREFIX)) : secret

        def happened_at(timestamp)
          Time.iso8601(timestamp.to_s)
        rescue ArgumentError
          Time.current
        end
      end
    end
  end
end
