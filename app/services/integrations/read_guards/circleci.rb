module Integrations
  module ReadGuards
    # api_read only ever sends a GET to CircleCI's API, under the version it reads, v2 (circleci.com/api/v2/openapi.json)
    # or v3 (circleci.com/docs/api/v3), so what the guard settles is which GETs answer secrets or something other than a
    # read Halon can use. A usage export answers presigned download addresses (getUsageExport, download_urls) and a
    # runner's tokens authenticate a runner (runner-tokens.md), so neither is read. A step's output is plain text that
    # get_job_logs reads. Environment variables, a project's or a context's, checkout keys, an OpenTelemetry exporter's
    # headers, signing certificates and the Slack connections notifications go through can carry a secret, so they are
    # read as names. A webhook's address can carry the receiver's token, so it keeps only its host.
    module Circleci
      extend PathReads

      VERSIONED = %r{\A/v[23]/}
      REFUSED = {
        %r{/usage_export_job(/|\z)|/usage/exports(/|\z)} => "A usage export answers addresses that download it without a key, so a read never fetches it.",
        %r{\A/v3/runner/tokens(/|\z)} => "A runner's token lets a machine take the organization's jobs, so a read never fetches it.",
        %r{\A/v3/jobs/[^/]+/(stdout|stderr)(/|\z)} => "A step's output is not read here. Read it with get_job_logs."
      }.freeze
      SECRET_PATHS = %r{/envvar(/|\z)|/environment-variables?(/|\z)|/checkout-key(/|\z)|/otel/exporters(/|\z)|/signing/(certificates|configs)(/|\z)|/notification/integrations(/|\z)}
      WEBHOOK_PATHS = %r{\A/v2/webhook(/|\z)|\A/v3/webhooks(/|\z)}

      def self.refusal(path, query)
        raise Refused, "The path starts with the version of CircleCI's API it reads, /v2 or /v3, such as /v2/me." unless path.match?(VERSIONED)

        super
      end
    end
  end
end
