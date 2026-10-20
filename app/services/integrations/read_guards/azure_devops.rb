module Integrations
  module ReadGuards
    # api_read only ever sends a GET to Azure DevOps' REST API (7.1, learn.microsoft.com/rest/api/azure/devops), so what
    # the guard settles is which GETs answer secrets or something other than a read Halon can use. A run's log, an
    # artifact, a file's content, a git blob or pack and a secure file are text or downloads that job_log and fetch_file
    # read instead, or that hold signed addresses. Variable groups and a pipeline's definition and runs answer the value
    # of every variable not marked secret, and a service connection's authorization can carry a credential, so they are
    # read as names. A service hook subscription's consumer inputs hold its address, its headers and its sign in, any of
    # which can carry the receiver's secret, so it is read as names too, its addresses kept to their host.
    module AzureDevops
      extend PathReads

      # Azure DevOps reads a path whatever its case, so each pattern matches any case too.
      REFUSED = {
        %r{/_apis/build/builds/[^/]+/logs(/|\z)}i => "A run's log is not read here. Read it with job_log.",
        %r{/_apis/pipelines/[^/]+/runs/[^/]+/logs(/|\z)}i => "A run's log is not read here. Read it with job_log.",
        %r{/_apis/build/builds/[^/]+/artifacts(/|\z)|/_apis/pipelines/[^/]+/runs/[^/]+/artifacts(/|\z)}i =>
          "A run's artifacts answer where they are kept, so a read never fetches them.",
        %r{/_apis/git/repositories/[^/]+/(items|blobs|packs)(/|\z)}i => "A file's content is not read here. Read a file with fetch_file.",
        %r{/_apis/distributedtask/securefiles(/|\z)}i => "A secure file is a download that holds a secret, so a read never fetches it.",
        %r{/_apis/tokens?(/|\z)|/_apis/tokenadmin(/|\z)}i => "Personal access tokens are never read."
      }.freeze
      SECRET_PATHS = %r{/_apis/hooks/subscriptions(/|\z)|/_apis/distributedtask/variablegroups(/|\z)|/_apis/serviceendpoint(/|\z)|/_apis/build/definitions(/|\z)|/_apis/pipelines/\d+(/runs)?(/|\z)}i
      WEBHOOK_PATHS = %r{/_apis/hooks/subscriptions(/|\z)}i
      # Reads the organization answers for, outside any project.
      ORGANIZATION_READS = %r{\A/_apis/(projects|hooks/publishers|hooks/consumers|distributedtask/pools|process)(/|\z)}i

      def self.organization_read?(path) = path.match?(ORGANIZATION_READS)
    end
  end
end
