class PostmortemSerializer < BaseSerializer
  object_as :postmortem

  type :string
  def id
    postmortem.id
  end

  attributes(
    title: { type: :string },
    status: { type: '"draft" | "in_progress" | "in_review" | "completed"' }
  )

  type :string
  def generated_by
    postmortem.generated_by.user.name
  end

  type :string
  def created_at
    postmortem.created_at.utc.iso8601
  end

  type :string
  def updated_at
    postmortem.updated_at.utc.iso8601
  end

  type :string, optional: true
  def html_content
    postmortem.html_content
  end
end
