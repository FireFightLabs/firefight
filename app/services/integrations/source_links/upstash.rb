module Integrations
  module SourceLinks
    # Links an Upstash result to the console page that shows it. Upstash's docs link to the console's Redis, QStash and
    # Workflow pages and give no address for one database. So a Redis result opens the list of databases, and a QStash
    # or Workflow result opens that product, where its Logs and DLQ tabs are. The console is the registry's site.
    class Upstash
      NAME = "the Upstash console".freeze
      REDIS = "redis".freeze
      QSTASH = "qstash".freeze
      WORKFLOW = "workflow".freeze
      SERVICE = "service".freeze
      # The QStash and Workflow tools, which take a service saying which of the two is meant.
      SHARED = %w[logs_list dlq_list dlq_manage].freeze

      # The console page of one product, or nil when the connection knows no console.
      def self.product(settings, product)
        site = settings&.site
        "#{site.delete_suffix('/')}/#{product}" if site.present?
      end

      def initialize(settings)
        @settings = settings
      end

      def link(tool_name:, arguments:, text: "")
        name = tool_name.to_s
        product = if name.start_with?("redis_") then REDIS
        elsif name.start_with?("workflow_") then WORKFLOW
        elsif name.start_with?("qstash_") then QSTASH
        elsif SHARED.include?(name) then arguments.to_h.stringify_keys[SERVICE] == WORKFLOW ? WORKFLOW : QSTASH
        end
        url = product && self.class.product(@settings, product)
        url && Telemetry::Link.new(provider: NAME, url: url)
      end
    end
  end
end
