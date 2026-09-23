# Before the agent starts, asks the code host which commit each affected service was running when the incident began.
# It goes through the same gateway wrapped tool the agent would call, so it is a numbered step the finding can cite,
# and the answer is kept with the facts, so a resumed run does not ask again.
class Investigation::RunningCode
  NOT_ON_CATALOG = "The service has no repository set in the catalog, so what was running is not known.".freeze
  NOT_CONNECTED = "No code host connection can say what was running. Connect GitHub and switch on running_commit.".freeze
  KEY = "running_code".freeze

  def initialize(investigation)
    @investigation = investigation
  end

  def note!
    facts = @investigation.seed_pack
    return facts if facts.key?(KEY)

    @investigation.update!(seed_pack: facts.merge(KEY => Array(facts["services"]).map { |service| running(service) }))
    @investigation.seed_pack
  end

  private

  def running(service)
    repository = service["repository"]
    { "service" => service["name"], "repository" => repository, "found" => found_for(repository) }
  end

  def found_for(repository)
    return NOT_ON_CATALOG if repository.blank?

    tool = running_commit_tool
    return NOT_CONNECTED unless tool

    Chat::Tools::Connection.new(@investigation, tool).call("repo" => repository, "at" => started_at.iso8601)
  end

  def running_commit_tool
    Integration::Tool.in_workspace(@investigation.workspace)
      .where(name: Integrations::Packs::Github::RUNNING_COMMIT, integrations: { provider: Integrations::GithubApp::PROVIDER_KEY })
      .first
  end

  # When the trouble began, which can be earlier than when someone declared it.
  def started_at
    incident = @investigation.incident
    incident&.detected_at || incident&.declared_at || @investigation.created_at
  end
end
