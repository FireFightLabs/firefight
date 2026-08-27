class PostmortemSerializer < BaseSerializer
  object_as :postmortem

  type :string
  def id
    postmortem.id
  end

  STATUS_UNION = Postmortem::STATUSES.map(&:inspect).join(" | ")
  GENERATION_UNION = Postmortem::GENERATION_STATES.map(&:inspect).join(" | ")

  attributes(
    title: { type: :string }
  )

  type STATUS_UNION
  def status
    postmortem.status
  end

  type GENERATION_UNION, optional: true
  def generation_state
    postmortem.generation_state
  end

  type :string, optional: true
  def generation_error
    postmortem.generation_error
  end

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

  # What the editor sends back when it saves, so a rewrite from an agent while
  # somebody is typing is refused rather than silently winning.
  type :number
  def version
    postmortem.content_version
  end

  type :string, optional: true
  def html_content
    postmortem.html_content
  end
end
