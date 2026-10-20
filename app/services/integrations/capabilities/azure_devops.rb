module Integrations
  module Capabilities
    # Azure DevOps answers for the repositories it puts on the map as every code host does (CodeHostAdapter), and for its
    # pipelines the same way: a pipeline's run history, how it stands, its newest failed job's log and what it deployed
    # are its own runs', named to its tools by the pipeline instead of the repository.
    module AzureDevops
      extend CodeHostAdapter

      HOST = "Azure DevOps".freeze
      KINDS = [ ResourceMap::KIND_REPOSITORY, ResourceMap::KIND_PIPELINE ].freeze
      # The pack has no redeploy, so a rollback is not offered through it.
      SUPPORTS = CodeHostAdapter::SUPPORTS.except(ROLLBACK).transform_values { KINDS }.freeze
      TOOLS = CodeHostAdapter::TOOLS.except(ROLLBACK).freeze
      WRAPPED = CodeHostAdapter::WRAPPED

      def self.subject(name) = "the repositories and pipelines #{name} puts on the map"

      def self.route(key, resource, given, tool: nil, settings: nil)
        routed = super
        return routed unless routed && resource.kind == ResourceMap::KIND_PIPELINE

        routed.with(arguments: routed.arguments.except("repo").merge("pipeline" => resource.external_id))
      end
    end
  end
end
