# Which files the code changes Halon writes may touch in the repositories a code host connection holds. Any may until
# an admin lists the paths that may not (CodeChange::PathPattern), since every change arrives as a pull request a person
# reviews. A coding agent that pushes its own change is told the same list, since Firefight cannot refuse what it pushes,
# and its pull request is checked against it once it opens (Integrations::ProtectedPullRequests).
module Integration::CodeChanges
  extend ActiveSupport::Concern

  MAX_PROTECTED_PATHS = 100

  # Whether the provider holds repositories a code change can be written to (the registry's holds_code).
  def holds_code? = IntegrationProvider.find(provider)&.holds_code == true

  # Why these patterns cannot be the connection's list, or nil when they can.
  def protected_paths_blocked_reason(patterns)
    return "#{display_name} holds no code, so it has no paths to keep out of code changes." unless holds_code?

    listed = self.class.listed_paths(patterns)
    return "List at most #{MAX_PROTECTED_PATHS} paths." if listed.size > MAX_PROTECTED_PATHS

    listed.lazy.filter_map { |pattern| CodeChange::PathPattern.refusal(pattern) }.first
  end

  # Replaces the list, answering why it was refused, or nil once it is saved.
  def protect_paths!(patterns)
    refusal = protected_paths_blocked_reason(patterns)
    return refusal if refusal

    update!(protected_paths: self.class.listed_paths(patterns))
    nil
  end

  # The changed paths the connection's list keeps out of a code change.
  def protected_among(paths) = self.class.kept_among(protected_paths, paths)

  # Why a change to these paths in repo is not opened, naming them and where the list is changed, or nil when none is kept out.
  def protected_paths_refusal(repo, paths)
    refused = protected_among(paths)
    return if refused.empty?

    "Halon may not change #{refused.sort.to_sentence} in #{repo}. An admin can change this under #{protected_paths_place}."
  end

  # Where an admin changes the list, in the words the page uses.
  def protected_paths_place
    provider_name = IntegrationProvider.find(provider)&.name || provider
    [ "Integrations", provider_name, (name unless provider_name.casecmp?(name.to_s.strip)), "Code changes" ].compact.join(", ")
  end

  # What saving said, for the toast and the chat.
  def protected_paths_words
    return "Halon may change any file in #{display_name}'s repositories. Every change arrives as a pull request for review." if protected_paths.empty?

    "Halon may not change #{protected_paths.to_sentence} in #{display_name}'s repositories."
  end

  class_methods do
    # The patterns as a person wrote them, one per line or as a list, trimmed, with blank and repeated ones left out.
    def listed_paths(patterns)
      Array(patterns).flat_map { |each| each.to_s.split(/\r?\n/) }.map(&:strip).compact_blank.uniq
    end

    # The patterns kept out of a change a coding agent writes in repo, given as owner/name or its address. Those are the
    # lists of the code host connections whose repository it is on the map, or of every code host connection when the
    # map does not say, so a path an admin listed is never left out for want of knowing where the repository lives.
    def protected_paths_for(workspace, repo)
      hosts = workspace.integrations.where(deleted_at: nil).includes(:integration_environments).select(&:holds_code?)
      name = repo.to_s.strip.sub(%r{\A(?:https?://|git@)[^/:]+[/:]}, "").delete_suffix(".git").delete_suffix("/")
      repositories = ResourceMap::Resource.present.where(workspace: workspace, kind: ResourceMap::KIND_REPOSITORY)
      rows = repositories.where(external_id: name).or(repositories.where(url: repo.to_s.strip))
                         .where.not(integration_environment_id: nil).distinct.pluck(:integration_environment_id)
      holders = hosts.select { |host| host.integration_environments.any? { |row| rows.include?(row.id) } }
      (holders.presence || hosts).flat_map(&:protected_paths).uniq
    end

    # The changed paths a coding agent's pull request in repo was asked to leave alone, by the same lists.
    def protected_among_for(workspace, repo, paths) = kept_among(protected_paths_for(workspace, repo), paths)

    # A comment Firefight writes on a coding agent's pull request that touched a kept path. Nobody asked for it, so it is
    # in the activity log as Halon's, under the coding agent's call it follows (via), naming whoever asked for the change.
    def record_pull_request_flag!(workspace, via:, url:, paths:, asked_by:, &)
      AbilityGateway.record_unattended!(
        principal: SystemAgent.investigator, action_key: via, workspace: workspace, params: { "pull_request" => url, "protected_paths" => paths },
        context: { source: AbilityGateway::SOURCE_CODE_AGENT, triggered_by_label: asked_by&.try(:actor_display_name) }, &
      )
    end

    def kept_among(patterns, paths)
      paths.select { |path| patterns.any? { |pattern| CodeChange::PathPattern.match?(pattern, path) } }
    end
  end
end
