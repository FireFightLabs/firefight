module Integrations
  module ReadGuards
    # api_read only ever sends a GET to GitHub's REST API (docs.github.com, REST API, and its description in
    # github/rest-api-description), so what the guard settles is which GETs answer something other than a read Halon can
    # use. An archive, a run's or a job's logs and an artifact answer a redirect to a short-lived address that downloads
    # them for anyone who has it (REST API, Download a repository archive, Download workflow run logs, Download job logs
    # for a workflow run, Download an artifact), so none is read here, and a job's log has job_log. Actions, Dependabot and
    # Codespaces secrets answer only their names (REST API, GitHub Actions Secrets), and a webhook's address can carry a
    # token of the receiver's, so both are read as names.
    module Github
      extend PathReads

      DOWNLOADS = "answers a short-lived address that downloads it for anyone who has it, so a read never fetches it".freeze
      REFUSED = {
        %r{\A/repos/[^/]+/[^/]+/(zipball|tarball)(/|\z)} => "A repository archive #{DOWNLOADS}. Read files with fetch_file or the code tools.",
        %r{\A/repos/[^/]+/[^/]+/actions/(runs/[^/]+(/attempts/[^/]+)?|jobs/[^/]+)/logs\z} => "A run's or a job's logs #{DOWNLOADS}. Read a job's log with job_log.",
        %r{\A/repos/[^/]+/[^/]+/actions/artifacts/[^/]+/[^/]+\z} => "An artifact #{DOWNLOADS}. Its name, size and run are at /repos/<owner>/<repo>/actions/artifacts/<id>."
      }.freeze
      SECRET_PATHS = %r{/(actions|dependabot|codespaces)/secrets(/|\z)|/environments/[^/]+/secrets(/|\z)|/hooks(/|\z)}
    end
  end
end
