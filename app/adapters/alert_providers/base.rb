module AlertProviders
  # normalize returns an array because providers like Alertmanager batch alerts per POST.
  # Each item carries only its own slice of the body.
  class Base
    NORMALIZED_FIELDS = %w[external_id fingerprint status title description service severity_raw team environment url].freeze

    RESOLVED_STATUS_VALUES = %w[resolved resolve ok recovered closed].freeze
    # The custom header a provider that signs nothing sends the source's token in.
    TOKEN_HEADER = "X-Firefight-Token".freeze
    # A provider that signs with a secret it generates itself, so the person pastes that secret into Firefight rather
    # than copying Firefight's token out.
    SECRET_FROM_PROVIDER = false
    # A provider whose webhook sends no header at all, so the source's token travels as the last segment of its address.
    # Only someone who can change the source sees that address whole.
    SECRET_IN_ADDRESS = false
    # Whether the source's fields come from dot paths the person maps on the source, rather than from the adapter.
    FIELD_MAPPING = false
    # A body the person pastes into a tool whose webhook body is a template they write, or nil when the tool's own body
    # is understood as it comes.
    TEMPLATE = nil
    # How long a signed request stays acceptable, for providers that sign a timestamp.
    SIGNATURE_TOLERANCE = 5.minutes

    def self.verify(headers:, raw_body:, source:)
      raise NotImplementedError
    end

    def self.token_matches?(provided, source)
      return false if provided.blank?

      ActiveSupport::SecurityUtils.secure_compare(provided, source.secret_token)
    end

    # The secret taken out of the address before the request was logged (AlertAddressSecret).
    def self.address_secret(headers) = headers[AlertAddressSecret::ENV_KEY].to_s.presence

    def self.bearer_token(headers)
      authorization = headers["Authorization"].to_s
      authorization.start_with?("Bearer ") ? authorization.delete_prefix("Bearer ").strip.presence : nil
    end

    # The password of an HTTP Basic Authorization header. The user name is whatever the tool asks for, so it is not
    # checked.
    def self.basic_password(headers)
      authorization = headers["Authorization"].to_s
      return unless authorization.start_with?("Basic ")

      decoded = Base64.strict_decode64(authorization.delete_prefix("Basic ").strip)
      decoded.split(":", 2).second.presence
    rescue ArgumentError
      nil
    end

    def self.hmac_hex(secret, data)
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, data.to_s)
    end

    def self.digest_matches?(provided, expected)
      provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided.to_s.strip, expected)
    end

    def self.fresh_timestamp?(value)
      value.to_s.match?(/\A\d+\z/) && (Time.current.to_i - value.to_i).abs <= SIGNATURE_TOLERANCE
    end

    # headers are the request's, for a provider that names each delivery in a header rather than in the body.
    def self.normalize(payload, source:, headers: {})
      raise NotImplementedError
    end

    # Whether a payload that normalizes to no alert is one the provider sends on purpose and expects accepted, such as a
    # test ping or an event the source does not turn into alerts. It is accepted with nothing stored, so the provider
    # never stops sending. Anything else that normalizes to nothing is refused as unrecognized.
    def self.ignored?(_payload) = false

    # What an on-call tool's webhook says happened to one of its pages, as an Integrations::Paging::Event, or nil for a
    # payload that is not about a page, which is every payload of a source that is not an on-call tool.
    def self.page_event(_payload) = nil

    # The key a page Firefight raised in the tool carries, as the tool sends it back, or nil.
    def self.page_key(_payload) = nil

    def self.normalize_status(value)
      RESOLVED_STATUS_VALUES.include?(value.to_s.downcase.strip) ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING
    end

    def self.item(fields, payload)
      { fields: fields, payload: payload }
    end

    # What the settings screen needs to offer the provider and walk someone through pointing it at a source.
    def self.descriptor(provider)
      { provider: provider, label: self::LABEL, steps: self::SETUP_STEPS,
        secretFromProvider: self::SECRET_FROM_PROVIDER, secretInAddress: self::SECRET_IN_ADDRESS, fieldMapping: self::FIELD_MAPPING, template: self::TEMPLATE }
    end
  end
end
