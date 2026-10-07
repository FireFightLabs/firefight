module Integrations
  module ErrorReaders
    # Cloudflare's server answers a failed request in execute as "Cloudflare API error: " and then either the HTTP status
    # and body, for an answer that is not JSON, or each error in Cloudflare's envelope as its code and message
    # (cloudflare/mcp, src/tools/execute.ts). A not found is a 404, or every error is one Cloudflare documents as the
    # thing named not being there.
    module Cloudflare
      SAID = /Cloudflare API error: (?<rest>.+)/m
      STATUS = /\A(?<status>\d{3}) /
      ENVELOPE_ERROR = /(?<code>\d+): (?<message>[^,]+)/
      # Could not route to the path, the identifier in it matching nothing (7003), a Pages project (8000007) and a Worker
      # (10007) that are not there.
      NOT_FOUND_CODES = %w[7003 8000007 10007].freeze
      NOT_FOUND_WORDS = /\bnot found\b|\bdoes not exist\b/i
      NOT_FOUND_STATUS = "404".freeze

      def self.not_found?(said)
        rest = said.to_s.match(SAID)&.[](:rest).to_s.strip
        return false if rest.empty?

        status = rest.match(STATUS)&.[](:status)
        return status == NOT_FOUND_STATUS if status

        errors = rest.scan(ENVELOPE_ERROR)
        errors.any? && errors.all? { |code, message| NOT_FOUND_CODES.include?(code) || message.match?(NOT_FOUND_WORDS) }
      end
    end
  end
end
