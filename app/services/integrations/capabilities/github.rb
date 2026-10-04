module Integrations
  module Capabilities
    # GitHub answers for the repositories it puts on the map, as every code host does (CodeHostAdapter). GitHub's deployments are the ones a GitHub Actions job naming an environment writes, or any pipeline that records them.
    module Github
      extend CodeHostAdapter

      HOST = "GitHub".freeze
      SUPPORTS = CodeHostAdapter::SUPPORTS
      TOOLS = CodeHostAdapter::TOOLS
      WRAPPED = CodeHostAdapter::WRAPPED
    end
  end
end
