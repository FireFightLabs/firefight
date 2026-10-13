# One change that landed on a version, as its history lists it: who did what, Halon's reason, and who accepted it when
# it was a suggestion of Halon's.
class WorkflowEditLineSerializer < BaseSerializer
  object_as :edit

  type :string
  def id
    edit.id
  end

  type :string
  def sentence
    edit.sentence
  end

  type :boolean
  def by_halon
    edit.by_halon?
  end

  type :string, optional: true
  def reason
    edit.reason
  end

  type :string, optional: true
  def accepted_by_name
    edit.decided_by&.actor_display_name if edit.status == Workflow::Edit::STATUS_ACCEPTED
  end

  type :string
  def created_at
    edit.created_at.iso8601
  end
end
