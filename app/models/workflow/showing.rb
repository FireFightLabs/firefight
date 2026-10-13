# What the canvas shows of a workflow: which version, and for a step that calls something through the gateway, whether
# the workflow's own identity may make that call yet. A run acts as that identity, which holds only what an admin
# granted it, so a step it cannot reach says so before anyone publishes.
module Workflow::Showing
  extend ActiveSupport::Concern

  # The version asked for, else the open draft, else the live one, else an empty one that is not saved yet, which the
  # first edit makes the draft.
  def shown_version(version_id = nil)
    (version_id.presence && versions.find_by(id: version_id)) || draft || live_version || empty_version
  end

  def empty_version
    Workflow::Version.new(workflow: self, status: Workflow::Version::STATUS_DRAFT, revision: 0, trigger: Workflow::Trigger.default,
                          steps: [], edges: [], outputs: {}, author_kind: Workflow::AUTHOR_PERSON)
  end

  # One change of Halon's: the edits it made together, or one edit it made on its own.
  HalonChange = Data.define(:key, :edits) do
    def reason = edits.first.reason
    def created_at = edits.first.created_at
    def version = edits.first.version
  end

  # Halon's changes that landed on the version shown, and on the live version a draft was opened from, newest first, each
  # of which can be undone.
  def halon_changes(shown)
    return [] unless shown.persisted?

    versions = [ shown, (live_version if shown.draft? && live_version && shown.parent_version_id == live_version.id) ].compact
    edits.landed.where(version: versions, author_kind: Workflow::AUTHOR_HALON).where.not(applied_revision: nil)
         .includes(:version, :decided_by, :source_chat, :source_run).order(:created_at).to_a
         .group_by { |edit| edit.change_set_id || edit.id }.map { |key, list| HalonChange.new(key: key, edits: list) }.reverse
  end

  # What the workflow's own identity does not hold yet of what a step needs (DefinedWorkflow::Reach::Needed), as a
  # sentence, or nil when it holds it all or the step needs nothing. Publishing grants it.
  def grant_needed_for(needs)
    resolved = agent && Ability::Resolver.resolve(agent, workspace)
    missing = needs.reject { |needed| resolved && needed.held_by?(agent, workspace, resolved) }
    return if missing.empty?

    "Needs #{missing.map { |needed| needed.label.downcase_first }.to_sentence}, which publishing grants to the workflow."
  end
end
