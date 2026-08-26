module Mcp
  module Tools
    # What the service-key tools report. The token itself appears once, in the
    # response that minted it, and never in a listing.
    module ApiKeyPayloads
      def self.summary(key)
        {
          prefix: key.token_prefix,
          name: key.name,
          active: key.active?,
          expires_at: key.expires_at&.utc&.iso8601,
          last_used_at: key.last_used_at&.utc&.iso8601,
          permissions: key.granted_permissions
        }.compact
      end
    end
  end
end
