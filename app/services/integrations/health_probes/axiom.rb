module Integrations
  module HealthProbes
    # Lists Axiom's datasets through listDatasets, which only works with a sign in Axiom accepts, and checks that the
    # datasets the connection was set up to read are among them, since every query names one. The tool is from Axiom's
    # MCP documentation (axiomhq/docs, console/intelligence/mcp-server/tools.mdx). It learns nothing to keep.
    class Axiom < RemoteReader
      # listDatasets, as Firefight names it.
      LIST_DATASETS = "listdatasets".freeze

      def check!
        result = call(LIST_DATASETS)
        return if result.nil?

        listed = Capabilities::Answers.text(result)
        refused!(LIST_DATASETS, result)

        missing = [ Capabilities::Axiom::LOGS_DATASET, Capabilities::Axiom::TRACES_DATASET ].filter_map do |key|
          name = settings&.field(key).to_s.strip
          name if name.present? && !listed.match?(/(?<![\w.-])#{Regexp.escape(name)}(?![\w.-])/)
        end
        raise Refused, "Axiom does not list #{missing.to_sentence} among this organization's datasets. Connect again with the names Axiom shows." if missing.any?
      end
    end
  end
end
