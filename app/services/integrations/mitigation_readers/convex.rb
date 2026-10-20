module Integrations
  module MitigationReaders
    # Pausing a Convex deployment is a mitigation for the whole tool (the registry's mitigation_tools), and undoing it
    # starts the deployment again with unpause_deployment.
    module Convex
      TOOL = "pause_deployment".freeze

      def self.mitigation?(tool, _arguments) = tool.name == TOOL

      def self.undo_words(tool, _arguments) = (Mitigations::STARTS_AGAIN if tool.name == TOOL)
    end
  end
end
