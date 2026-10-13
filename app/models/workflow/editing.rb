# People and Halon change the same workflows, one attributed edit at a time. A person's edit lands on the draft, which
# is opened from the live version when there is none. Halon's edit lands directly only on a workflow it is building
# alone, one with nothing live and no draft a person touched. Anything else Halon changes is a proposal on top of what
# is there, which a person accepts or dismisses.
module Workflow::Editing
  extend ActiveSupport::Concern

  # The open draft, or a new one made from the given version, the live one by default, or empty.
  def open_draft!(by:, halon: false, reason: nil, from: live_version)
    attempts = 0
    begin
      draft || transaction(requires_new: true) do
        versions.create!(
          number: (versions.maximum(:number) || 0) + 1, status: Workflow::Version::STATUS_DRAFT,
          trigger: from&.trigger || Workflow::Trigger.default, steps: from&.steps || [], edges: from&.edges || [], outputs: from&.outputs || {},
          author_kind: halon ? Workflow::AUTHOR_HALON : Workflow::AUTHOR_PERSON, author: by, reason: reason, parent_version: from
        )
      end
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts < 3
      raise
    end
  end

  # Applies one operation, or proposes it when Halon may not apply it here. Returns the edit. base_revision is the
  # draft revision the editor saw, so a change made since to the same step refuses the edit with who made it.
  def edit!(operation:, payload:, by:, halon: false, reason: nil, base_revision: nil, change_set_id: nil, source_run: nil, source_chat: nil)
    prepared = Workflow::Edit::Operations.prepared(operation, payload)
    attributes = { author_kind: halon ? Workflow::AUTHOR_HALON : Workflow::AUTHOR_PERSON, author: by, reason: reason,
                   source_run: source_run, source_chat: source_chat, operation: operation,
                   payload: Workflow::Edit.named(operation, prepared, (draft || live_version)&.steps_by_id || {}) }
    return propose!(attributes, change_set_id) if halon && !halon_applies_directly?
    return rename_workflow!(attributes) if Workflow::Edit.workflow_rename?(operation, payload)

    open_draft!(by: by, halon: halon, reason: reason).apply_edit!(attributes.merge(change_set_id: change_set_id), base_revision: base_revision)
  end

  # Takes Halon's changes back out of the open draft, or of the live version into a new draft, keeping everything people
  # did around them. Each step back is a person's edit, grouped as one change, so the history says who undid it. All
  # of it lands or none does. Returns the edits it made.
  def undo_halon!(halon_edits, by:)
    change_set_id = SecureRandom.uuid
    transaction do
      reload
      blocked = undo_blocked_reason(halon_edits)
      raise Workflow::Edit::Refused, blocked if blocked

      # Held until the undo lands, so an edit made meanwhile waits and is checked against it rather than overwritten.
      version = (draft || live_version).lock!
      operations = Workflow::Edit::Diff.operations(version.snapshot, undone_content(version, halon_edits))
      raise Workflow::Edit::Refused, "Halon's change is already undone." if operations.empty?

      operations.map do |operation, payload|
        edit!(operation: operation, payload: payload, by: by, reason: UNDO_REASON, change_set_id: change_set_id)
      end
    end
  end

  UNDO_REASON = "Undid Halon's change.".freeze

  # Why Halon's edits cannot be undone as one, as a sentence, or nil. Only edits that landed on the open draft or the
  # live version can be.
  def undo_blocked_reason(halon_edits)
    return "Choose a change of Halon's to undo." if halon_edits.empty?
    return "Only a change Halon made can be undone here." unless halon_edits.all?(&:by_halon?)
    return "Only a change that landed can be undone." unless halon_edits.all? { |edit| Workflow::Edit::LANDED.include?(edit.status) && edit.applied_revision }

    "Only a change in the open draft or the live version can be undone." unless (halon_edits.map(&:version_id) - undoable_version_ids).empty?
  end

  # Nothing is live and no person has touched the draft, so Halon is building it alone.
  def halon_applies_directly?
    return false if live_version

    current = draft
    current.nil? || (current.by_halon? && current.edits.where.not(author_kind: Workflow::AUTHOR_HALON).none?)
  end

  # Halon's proposals waiting for a person, oldest first.
  def proposals = edits.where(status: Workflow::Edit::STATUS_PROPOSED).order(:created_at)

  # Accepts each of the chosen proposals in the order Halon made them. All land or none does, so a refusal halfway leaves
  # every one of them waiting. Returns how many were accepted.
  def accept_suggestions!(chosen, by:)
    decide_all(chosen) { |suggestion| suggestion.accept!(by: by) }
  end

  def dismiss_suggestions!(chosen, by:)
    decide_all(chosen) { |suggestion| suggestion.dismiss!(by: by) }
  end

  # The open draft and the live version it came from, or the live version alone when no draft is open.
  def undoable_version_ids
    current = draft
    return [ live_version&.id ].compact unless current

    [ current.id, (current.parent_version_id if live_version && current.parent_version_id == live_version.id) ].compact
  end

  private

  def decide_all(chosen, &decide)
    list = chosen.reorder(:created_at).to_a
    raise Workflow::Edit::Refused, "No suggestion of Halon's is waiting." if list.empty?

    transaction { list.each(&decide) }
    list.size
  end

  # The version's content made again without Halon's edits. A change of Halon's on the live version under the open
  # draft is left out of where the draft started, so what was done in the draft since is made again on top of it.
  def undone_content(version, halon_edits)
    here, under = halon_edits.partition { |edit| edit.version_id == version.id }
    start = under.empty? ? version.starting_content : version.parent_version.content_without(under)
    version.content_without(here, from: start)
  end

  def propose!(attributes, change_set_id)
    problem = Workflow::Version.secret_problem(attributes[:payload])
    raise Workflow::Edit::Refused, problem if problem

    base = draft || live_version
    edits.create!(attributes.merge(status: Workflow::Edit::STATUS_PROPOSED, version: base, base_revision: base&.revision,
                                   change_set_id: change_set_id || SecureRandom.uuid,
                                   targets: Workflow::Edit::Operations.targets(attributes[:operation], attributes[:payload])))
  end

  def rename_workflow!(attributes)
    transaction do
      update!(name: attributes[:payload]["name"])
      edits.create!(attributes.merge(status: Workflow::Edit::STATUS_APPLIED, targets: [ Workflow::Edit::TARGET_WORKFLOW ]))
    end
  end
end
