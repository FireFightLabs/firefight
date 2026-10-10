module Integrations
  module Clis
    # kubectl, which the image wraps so it reaches the server and token the box hands it (FIREFIGHT_KUBE_SERVER and
    # FIREFIGHT_KUBE_TOKEN), since kubectl reads neither from the environment. kubectl keeps a server address's path and
    # sends the token as a bearer token, so every request reaches the relay as a GET under /api or /apis, which is what
    # api_read reads, discovery included. Through Firefight it only reads. A change goes through Halon's own tools, such as
    # rollout_restart or scale_workload, so the person confirms it and its safeguards run.
    module Kubernetes
      COMMAND = "kubectl".freeze
      TOOL = ApiReads::TOOL
      SERVER_VARIABLE = "FIREFIGHT_KUBE_SERVER".freeze
      TOKEN_VARIABLE = "FIREFIGHT_KUBE_TOKEN".freeze

      def self.env(base_url, token) = { SERVER_VARIABLE => base_url, TOKEN_VARIABLE => token }

      def self.arguments(verb, path, query, _body)
        unless verb.to_s.upcase == ApiReads::GET
          raise Refused, "Through Firefight, kubectl only reads. Make a change with Halon's own tools, such as rollout_restart, " \
                         "scale_workload or rollout_undo, so the person confirms it."
        end

        { "path" => "/#{path.to_s.delete_prefix('/')}", "query" => query.presence }.compact
      end

      def self.answer(relayed) = relayed
    end
  end
end
