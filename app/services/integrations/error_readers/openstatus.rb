module Integrations
  module ErrorReaders
    # OpenStatus's server calls its own services, and a lookup that matches nothing is its NotFoundError, said as
    # "<entity> <id> not found" or "<entity> not found" and nothing else (openstatusHQ/openstatus,
    # packages/services/src/errors.ts and apps/server/src/routes/mcp/adapter.ts). Any other error carries other words.
    module Openstatus
      NOT_FOUND = /\A[A-Za-z_ ]+(?: \S+)? not found\z/

      def self.not_found?(said) = said.strip.match?(NOT_FOUND)
    end
  end
end
