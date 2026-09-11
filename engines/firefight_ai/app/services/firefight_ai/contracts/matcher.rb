module FirefightAi
  module Contracts
    # A signature in, a confirmed pattern or nothing out. Never a model deciding alone.
    module Matcher
      Signature = Data.define(:alert_fingerprints, :issue_codes, :entity_types, :incident_type)

      def match(signature)
        raise NotImplementedError, "#{self.class.name} must implement match(signature)"
      end
    end
  end
end
