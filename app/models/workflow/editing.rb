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
    payload = sealed_payload(operation, payload, keep: !halon || halon_applies_directly?)
    attributes = { author_kind: halon ? Workflow::AUTHOR_HALON : Workflow::AUTHOR_PERSON, author: by, reason: reason,
                   source_run: source_run, source_chat: source_chat, operation: operation,
                   payload: Workflow::Edit::Operations.prepared(operation, payload) }
    return propose!(attributes, change_set_id) if halon && !halon_applies_directly?
    return rename_workflow!(attributes) if Workflow::Edit.workflow_rename?(operation, payload)

    open_draft!(by: by, halon: halon, reason: reason).apply_edit!(attributes, base_revision: base_revision)
  end

  # Nothing is live and no person has touched the draft, so Halon is building it alone.
  def halon_applies_directly?
    return false if live_version

    current = draft
    current.nil? || (current.by_halon? && current.edits.where.not(author_kind: Workflow::AUTHOR_HALON).none?)
  end

  # Halon's proposals waiting for a person, oldest first.
  def proposals = edits.where(status: Workflow::Edit::STATUS_PROPOSED).order(:created_at)

  private

  # A new trigger's private values are kept on the workflow before the edit is recorded, so the edit never holds them. A
  # proposal does not set them, since a value only goes in when a person or Halon building alone puts it there.
  def sealed_payload(operation, payload, keep:)
    payload = payload.to_h.deep_stringify_keys
    return payload unless operation == Workflow::Edit::OPERATION_CHANGE_TRIGGER && payload["trigger"].is_a?(Hash)

    stripped, values = Workflow::Trigger.sealed(payload["trigger"])
    keep_private_inputs!(values) if keep
    payload.merge("trigger" => stripped)
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
