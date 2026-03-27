class PostmortemUpdateSerializer < BaseSerializer
  object_as :update

  type :string
  def id
    update.id
  end

  attributes(
    update_type: { type: '"generated" | "edited" | "ai_edited"' }
  )

  type "string[]"
  def changed_sections
    update.changed_sections || []
  end

  type :string
  def edited_by
    update.edited_by.user.name
  end

  type :string
  def created_at
    update.created_at.utc.iso8601
  end
end
