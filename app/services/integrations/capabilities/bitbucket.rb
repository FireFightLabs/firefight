module Integrations
  module Capabilities
    # Bitbucket answers for the repositories it puts on the map, as every code host does (CodeHostAdapter). Its
    # deployments are the ones its pipelines record against an environment.
    module Bitbucket
      extend CodeHostAdapter

      HOST = "Bitbucket".freeze
      SUPPORTS = CodeHostAdapter::SUPPORTS
      TOOLS = CodeHostAdapter::TOOLS
      WRAPPED = CodeHostAdapter::WRAPPED
    end
  end
end
