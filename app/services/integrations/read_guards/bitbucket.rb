module Integrations
  module ReadGuards
    # api_read only ever sends a GET to Bitbucket Cloud's REST API (2.0, developer.atlassian.com/cloud/bitbucket/rest), so
    # what the guard settles is which GETs answer secrets or something other than a read Halon can use. A repository's
    # downloads and a pipeline step's log answer a redirect to where they are kept, a file's source, a diff and a patch
    # answer plain text, and fetch_file, compare_commits and job_log read those instead. Pipeline and deployment
    # variables answer the value of every one not marked secured (REST API, Pipelines, List variables for a repository),
    # so they are read as names. A webhook's address can carry a token of the receiver's, so it keeps only its host.
    module Bitbucket
      extend PathReads

      REFUSED = {
        %r{\A/repositories/[^/]+/[^/]+/downloads/[^/]+} => "A repository's download answers where the file is kept, so a read never fetches it. Its list is at /repositories/<workspace>/<repo>/downloads.",
        %r{\A/repositories/[^/]+/[^/]+/pipelines/[^/]+/steps/[^/]+/(log|logs)(/|\z)} => "A step's log is not read here. Read it with job_log.",
        %r{\A/repositories/[^/]+/[^/]+/src/} => "A file's source is plain text, not read here. Read a file with fetch_file.",
        %r{\A/repositories/[^/]+/[^/]+/(diff|patch)/} => "A diff or a patch is plain text, not read here. Compare two commits with compare_commits."
      }.freeze
      SECRET_PATHS = %r{/variables(/|\z)}
      WEBHOOK_PATHS = %r{/hooks(/|\z)}
    end
  end
end
