module Integrations
  module Capabilities
    # GitLab answers for the repositories it puts on the map, as every code host does (CodeHostAdapter). GitLab's deployments are the ones its environments record.
    module Gitlab
      extend CodeHostAdapter

      HOST = "GitLab".freeze
      SUPPORTS = CodeHostAdapter::SUPPORTS
      TOOLS = CodeHostAdapter::TOOLS
      WRAPPED = CodeHostAdapter::WRAPPED
    end
  end
end
