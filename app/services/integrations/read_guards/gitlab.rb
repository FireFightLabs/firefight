module Integrations
  module ReadGuards
    # api_read only ever sends a GET to GitLab's REST API (doc/api in gitlab-org/gitlab), written after /api/v4, so what
    # the guard settles is which GETs answer secrets or something other than a read Halon can use. A Terraform state
    # holds the values of everything it manages, passwords included (doc/user/infrastructure/iac/terraform_state.md), so
    # it is never read. A job's artifacts, a repository archive, a secure file and a package file are downloads, and a
    # raw file or a job's log answer plain text that fetch_file and job_log read instead. CI/CD variables answer their
    # values (doc/api/project_level_variables.md, group_level_variables.md, instance_level_ci_variables.md), a pipeline
    # trigger answers its token (doc/api/pipeline_triggers.md), and an integration's settings and a webhook's address can
    # carry a token, so all of them are read as names.
    module Gitlab
      extend PathReads

      REFUSED = {
        %r{/terraform/state(/|\z)} => "A Terraform state holds the values of everything it manages, passwords included, so a read never fetches it.",
        %r{/jobs/[^/]+/(artifacts|trace)(/|\z)|/jobs/artifacts(/|\z)} =>
          "A job's log and artifacts are not read here. Read a job's log with job_log.",
        %r{/repository/(archive|files/[^/]+/raw|blobs/[^/]+/raw)} => "A raw file or an archive is not read here. Read a file with fetch_file.",
        %r{/secure_files/[^/]+/download|/packages/.+/(download|files/[^/]+)\z|/packages/generic/} =>
          "A secure file or a package's file is a download, so a read never fetches it. Its details are listed without /download."
      }.freeze
      SECRET_PATHS = %r{/variables(/|\z)|/triggers(/|\z)|/integrations(/|\z)|/services(/|\z)|/hooks(/|\z)}
    end
  end
end
