class ApiKeySerializer < BaseSerializer
  object_as :key

  type :string
  def id
    key.id
  end

  attributes(
    name: { type: :string },
    token_prefix: { type: :string },
    active: { type: :boolean }
  )

  type "Record<string, string[]>"
  def permissions
    key.permissions
  end

  type :string
  def kind
    key.personal? ? "personal" : "service"
  end

  type :string, optional: true
  def owner_name
    key.on_behalf_of&.display_name
  end

  type :string
  def created_by
    key.created_by.user.name
  end

  type :string
  def created_at
    key.created_at.utc.iso8601
  end

  type :string, optional: true
  def last_used_at
    key.last_used_at&.utc&.iso8601
  end

  type :string, optional: true
  def expires_at
    key.expires_at&.utc&.iso8601
  end
end
