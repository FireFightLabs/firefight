module AlertProviders
  # normalize returns an array because providers like Alertmanager batch alerts per POST.
  # Each item carries only its own slice of the body.
  class Base
    NORMALIZED_FIELDS = %w[external_id fingerprint status title description service severity_raw team environment].freeze

    RESOLVED_STATUS_VALUES = %w[resolved resolve ok recovered closed].freeze

    def self.verify(headers:, raw_body:, source:)
      raise NotImplementedError
    end

    def self.normalize(payload, source:)
      raise NotImplementedError
    end

    # Whether a payload that normalizes to no alert is one the provider sends on purpose and expects accepted, such as a
    # test ping or an event the source does not turn into alerts. It is accepted with nothing stored, so the provider
    # never stops sending. Anything else that normalizes to nothing is refused as unrecognized.
    def self.ignored?(_payload) = false

    def self.normalize_status(value)
      RESOLVED_STATUS_VALUES.include?(value.to_s.downcase.strip) ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING
    end

    def self.item(fields, payload)
      { fields: fields, payload: payload }
    end
  end
end
