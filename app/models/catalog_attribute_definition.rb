class CatalogAttributeDefinition < ApplicationRecord
  TYPE_TEXT = "text"
  TYPE_NUMBER = "number"
  TYPE_BOOLEAN = "boolean"
  TYPE_SELECT = "select"
  TYPE_LIST = "list"
  TYPE_REFERENCE = "reference"
  TYPE_SLACK_CHANNEL = "slack_channel"
  TYPE_WORKSPACE_MEMBER = "workspace_member"
  TYPE_WORKSPACE_MEMBERS = "workspace_members"
  ATTRIBUTE_TYPES = [
    TYPE_TEXT, TYPE_NUMBER, TYPE_BOOLEAN, TYPE_SELECT, TYPE_LIST, TYPE_REFERENCE,
    TYPE_SLACK_CHANNEL, TYPE_WORKSPACE_MEMBER, TYPE_WORKSPACE_MEMBERS
  ].freeze

  # The types whose values are workspace membership ids. Member pickers and
  # name resolution both key off this list.
  MEMBER_TYPES = [ TYPE_WORKSPACE_MEMBER, TYPE_WORKSPACE_MEMBERS ].freeze

  # Which job an attribute does for alert routing. Routing asks for the role,
  # never for a slug, so a workspace can name its attributes anything. Each
  # role only fits the attribute types whose values it reads.
  ROLE_MEMBERS = "members"
  ROLE_MANAGER = "manager"
  ROLE_NOTIFICATION_CHANNEL = "notification_channel"
  ROLES = [ ROLE_MEMBERS, ROLE_MANAGER, ROLE_NOTIFICATION_CHANNEL ].freeze

  ROLE_LABELS = {
    ROLE_MEMBERS => "Members",
    ROLE_MANAGER => "Manager",
    ROLE_NOTIFICATION_CHANNEL => "Notification channel"
  }.freeze

  ATTRIBUTE_TYPES_BY_ROLE = {
    ROLE_MEMBERS => MEMBER_TYPES,
    ROLE_MANAGER => [ TYPE_WORKSPACE_MEMBER ],
    ROLE_NOTIFICATION_CHANNEL => [ TYPE_SLACK_CHANNEL ]
  }.freeze

  belongs_to :catalog_type
  has_many :catalog_entry_relationships

  validates :slug, presence: true, uniqueness: { scope: :catalog_type_id }
  validates :name, presence: true
  validates :attribute_type, presence: true, inclusion: { in: ATTRIBUTE_TYPES }
  validates :position, presence: true
  validates :role, inclusion: { in: ROLES }, uniqueness: { scope: :catalog_type_id }, allow_nil: true
  validate :role_fits_attribute_type

  validate :slug_immutable, on: :update
  validate :attribute_type_immutable, on: :update
  validate :select_requires_options
  validate :reference_requires_type_id

  scope :ordered, -> { order(:position) }
  scope :reference_type, -> { where(attribute_type: TYPE_REFERENCE) }

  def reference? = attribute_type == TYPE_REFERENCE
  def select? = attribute_type == TYPE_SELECT

  # What a reference attribute points at. Callers that write a type name it by
  # slug rather than by id, so reading one back has to answer in the same terms.
  def reference_type
    return nil unless reference? && reference_type_id.present?

    catalog_type.workspace.catalog_type_by_id(reference_type_id)
  end

  def reference_type_id
    config["reference_type_id"]
  end

  def options
    config["options"]
  end

  private

  def slug_immutable
    if slug_changed?
      errors.add(:slug, "cannot be changed after creation")
    end
  end

  def attribute_type_immutable
    if attribute_type_changed?
      errors.add(:attribute_type, "cannot be changed after creation")
    end
  end

  def select_requires_options
    return unless attribute_type == TYPE_SELECT

    if config["options"].blank? || !config["options"].is_a?(Array) || config["options"].empty?
      errors.add(:base, "needs at least one option")
    end
  end

  def reference_requires_type_id
    return unless attribute_type == TYPE_REFERENCE

    if config["reference_type_id"].blank?
      errors.add(:base, "needs a type to reference")
    end
  end

  def role_fits_attribute_type
    return if role.blank?

    allowed = ATTRIBUTE_TYPES_BY_ROLE.fetch(role, [])
    return if allowed.include?(attribute_type)

    errors.add(:role, "#{ROLE_LABELS[role]} needs a #{allowed.join(' or ')} attribute")
  end
end
