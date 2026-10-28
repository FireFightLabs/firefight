module SubscriptionProxy
  # Talks to the subscription proxy: its management API (sign-ins, the credentials they leave, their state) with the
  # management key and its model list with the client key. Every failed call is kept as a PlatformCallFailure for the
  # workspace it was made for, where the console finds it, and raised as a SubscriptionProxy error. Nothing here reads
  # or returns a token: the proxy keeps them, and a credential is known by its name.
  class Client
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20
    MANAGEMENT = "/v8/management".freeze
    # The proxy answers a sign-in's state with one of these.
    STATUS_WAITING = "wait".freeze
    STATUS_DONE = "ok".freeze
    VERSION_HEADER = "X-Cpa-Version".freeze
    # A credential's name as the proxy writes it, never a wildcard, so a delete can only ever name one.
    CREDENTIAL_NAME = /\A[\w.@+-]+\.json\z/

    # A sign-in the proxy started. url is where the person signs in. user_code is the code a device sign-in asks them
    # to enter, nil for one that sends the browser back to an address they paste. expires_at is when the proxy stops
    # waiting, nil when it does not say.
    SignIn = Data.define(:state, :url, :user_code, :expires_at) do
      def device? = user_code.present?
    end

    # What a sign-in's start names, read by the proxy's post-auth hook.
    SIGN_IN_PARAM = "firefight_sign_in".freeze
    WORKSPACE_PARAM = "firefight_workspace".freeze
    REFUSED_TAKEN = "taken".freeze
    REFUSED_UNNAMED = "unnamed".freeze

    # One credential as the proxy reports it. quota holds the limit signals its provider sent with its last answer.
    # sign_in_id is the id of the Firefight sign-in that made it, which the proxy's hook keeps as its note.
    Credential = Data.define(:name, :provider, :email, :label, :status, :status_message, :disabled, :unavailable,
                             :next_retry_after, :quota, :quota_observed_at, :created_at, :updated_at, :succeeded, :failed, :sign_in_id)

    # A model a workspace's sign-ins serve, by its own name.
    Model = Data.define(:id, :name, :context_window, :max_output_tokens, :input_modalities)

    TEXT = "text".freeze
    GEMINI_LISTING = "/v1beta/models".freeze
    ANTHROPIC_VERSION = "2023-06-01".freeze

    def initialize(workspace: nil)
      raise NotConfigured, "the subscription proxy is not configured" unless SubscriptionProxy.configured?

      @workspace = workspace
    end

    # The proxy's version when it answers its health check.
    def health
      response = call(:health, Net::HTTP::Get, "/healthz", key: nil)
      response[VERSION_HEADER]
    end

    # The settings the proxy runs with, read back so Firefight can confirm the ones that keep workspaces apart.
    def settings = json(call(:settings, Net::HTTP::Get, "#{MANAGEMENT}/config"))

    # Starts a sign-in named by Firefight's own id for it, for this client's workspace. The proxy stamps the credential
    # it saves with both (deploy/subscription-proxy/firefight_sign_in.go), so the credential is found by the id, and
    # carries the workspace's prefix from the moment it exists.
    def start_sign_in(provider, sign_in_id:)
      query = { provider: provider, SIGN_IN_PARAM => sign_in_id, WORKSPACE_PARAM => SubscriptionProxy.prefix_for(@workspace) }
      body = json(call(:start_sign_in, Net::HTTP::Get, "#{MANAGEMENT}/oauth/auth-url?#{query.to_query}"))
      expires_in = body["expires_in"].to_i
      SignIn.new(state: body.fetch("state"), url: body.fetch("url"), user_code: body["user_code"].presence,
                 expires_at: expires_in.positive? ? expires_in.seconds.from_now : nil)
    end

    # Why the proxy refused to save a sign-in's credential: REFUSED_TAKEN when the login is connected to another
    # workspace, REFUSED_UNNAMED when the sign-in carried no id, nil otherwise.
    def sign_in_refusal(sign_in_id)
      body = json(call(:sign_in_refusal, Net::HTTP::Get, "/firefight/sign-ins/#{CGI.escape(sign_in_id.to_s)}"))
      body["refused"].presence
    end

    # :waiting, :done, or the proxy's reason it failed as a string.
    def sign_in_status(state)
      raise ArgumentError, "a sign-in's state is required" if state.blank?

      body = json(call(:sign_in_status, Net::HTTP::Get, "#{MANAGEMENT}/oauth/status?#{{ state: state }.to_query}"))
      case body["status"]
      when STATUS_WAITING then :waiting
      when STATUS_DONE then :done
      else body["error"].presence || "the sign-in failed"
      end
    end

    # Hands the proxy the code from the address the person's browser landed on.
    def finish_sign_in(provider, state:, code:)
      call(:finish_sign_in, Net::HTTP::Post, "#{MANAGEMENT}/oauth/callback", body: { provider: provider, state: state, code: code })
      nil
    end

    def cancel_sign_in(state)
      return if state.blank?

      call(:cancel_sign_in, Net::HTTP::Delete, "#{MANAGEMENT}/oauth/session?#{{ state: state }.to_query}")
      nil
    end

    def credentials
      json(call(:credentials, Net::HTTP::Get, "#{MANAGEMENT}/credentials")).fetch("files", []).map { |file| credential(file) }
    end

    # Higher goes first among one workspace's credentials for the same model.
    def prioritize(name, priority)
      patch(:prioritize, name, priority: priority)
    end

    # A credential the proxy no longer holds is already gone, which is what a delete asks for.
    def delete(name)
      checked = checked_name(name)
      call(:delete_credential, Net::HTTP::Delete, "#{MANAGEMENT}/credentials?#{{ name: checked }.to_query}", missing_is_done: true)
      nil
    end

    # The models a workspace's sign-ins serve that answer in text, by their own names (without the workspace's prefix),
    # with how much each reads and writes and what it takes besides text. The Anthropic shaped list carries the sizes
    # and the Gemini shaped one what goes in and out.
    def models_for(workspace)
      prefix = "#{SubscriptionProxy.prefix_for(workspace)}/"
      client_key = SubscriptionProxy.settings.client_key
      sized = json(call(:models, Net::HTTP::Get, "#{INFERENCE_PATH}/models", key: nil,
                        headers: { "x-api-key" => client_key, "anthropic-version" => ANTHROPIC_VERSION }))
      shapes = json(call(:models, Net::HTTP::Get, GEMINI_LISTING, key: nil, headers: { "x-goog-api-key" => client_key }))
      kinds = shapes.fetch("models", []).to_h { |model| [ model["name"].to_s.delete_prefix("models/").delete_prefix(prefix), model ] }
      sized.fetch("data", []).filter_map do |model|
        id = model["id"].to_s
        next unless id.start_with?(prefix)

        name = id.delete_prefix(prefix)
        kind = kinds[name] || {}
        next unless Array(kind["supportedOutputModalities"]).include?(TEXT)

        Model.new(id: name, name: model["display_name"].presence || name, context_window: model["max_input_tokens"].to_i,
                  max_output_tokens: model["max_tokens"].to_i, input_modalities: Array(kind["supportedInputModalities"]))
      end.uniq(&:id)
    end

    private

    def patch(operation, name, fields)
      call(operation, Net::HTTP::Patch, "#{MANAGEMENT}/credentials/fields", body: fields.merge(name: checked_name(name)))
      nil
    end

    def checked_name(name)
      raise ArgumentError, "not a credential's name: #{name.inspect}" unless name.to_s.match?(CREDENTIAL_NAME)

      name.to_s
    end

    def credential(file)
      quota = file["quota"].is_a?(Hash) ? file["quota"] : {}
      Credential.new(
        name: file["name"].to_s, provider: file["provider"].to_s, email: file["email"].presence, label: file["label"].presence,
        status: file["status"].to_s, status_message: file["status_message"].presence, disabled: file["disabled"] == true,
        unavailable: file["unavailable"] == true, next_retry_after: time(file["next_retry_after"]),
        quota: quota["signals"].is_a?(Hash) ? quota["signals"] : {}, quota_observed_at: time(quota["observed_at"]),
        created_at: time(file["created_at"]), updated_at: time(file["updated_at"]),
        succeeded: file["success"].to_i, failed: file["failed"].to_i, sign_in_id: file["note"].presence
      )
    end

    def time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      nil
    end

    def json(response)
      JSON.parse(response.body.presence || "{}")
    rescue JSON::ParserError
      raise Refused.new("the subscription proxy answered something that is not JSON", status: response.code.to_i)
    end

    def call(operation, verb, path, key: SubscriptionProxy.settings.management_key, body: nil, headers: {}, missing_is_done: false)
      uri = URI("#{SubscriptionProxy.url}#{path}")
      request = verb.new(uri)
      request["Authorization"] = "Bearer #{key}" if key
      headers.each { |name, value| request[name] = value }
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      response = transport(uri, request)
      return response if response.is_a?(Net::HTTPSuccess)
      return response if missing_is_done && response.is_a?(Net::HTTPNotFound)

      refused = response.is_a?(Net::HTTPNotFound) ? NotFound : Refused
      raise refused.new("the subscription proxy answered #{response.code}: #{reason(response)}", status: response.code.to_i)
    rescue Error => error
      PlatformCallFailure.note(workspace: @workspace, platform: PLATFORM, operation: operation, error: error)
      raise
    end

    def reason(response)
      parsed = JSON.parse(response.body.to_s)
      parsed.is_a?(Hash) ? (parsed["error"] || parsed["message"]).to_s.truncate(200) : ""
    rescue JSON::ParserError
      response.body.to_s.truncate(200)
    end

    def transport(uri, request)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
    rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError, IOError, Net::HTTPBadResponse => error
      raise Unreachable, "could not reach the subscription proxy (#{error.class.name})"
    end
  end
end
