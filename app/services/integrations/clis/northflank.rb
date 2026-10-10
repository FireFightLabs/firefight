module Integrations
  module Clis
    # Northflank's own command line tool (@northflank/cli). Its API client takes the API's address and a token from the
    # environment (NF_API_BASE_URL and NF_API_TOKEN, @northflank/js-client's environment context), and calls
    # <address>/v1/projects/<project>/..., which is exactly what api_request reaches inside a project. Calls outside a
    # project, and logs and exec, which stream over a socket, do not go through Firefight, so it says to use Halon's own
    # tools for those.
    module Northflank
      COMMAND = "northflank".freeze
      TOOL = Capabilities::Northflank::API
      INSIDE_PROJECT = %r{\Av1/projects/(?<project>[A-Za-z0-9_-]+)/(?<path>[A-Za-z0-9_/-]+)\z}

      def self.env(base_url, token) = { "NF_API_BASE_URL" => base_url, "NF_API_TOKEN" => token }

      def self.arguments(verb, path, query, body)
        inside = path.to_s.delete_prefix("/").delete_suffix("/").match(INSIDE_PROJECT)
        unless inside
          raise Refused, "Through Firefight, northflank reaches what is inside a project (v1/projects/<project>/...), not #{path}. " \
                         "For logs, metrics and anything else, use ff search_logs, ff query_metrics or ff tools."
        end

        { "method" => verb.to_s.upcase, "path" => inside[:path], Packs::Northflank::PROJECT => inside[:project],
          "query" => query.presence, "body" => body.presence }.compact
      end

      def self.answer(relayed) = relayed
    end
  end
end
