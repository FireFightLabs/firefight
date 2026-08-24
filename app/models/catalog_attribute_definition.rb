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

  belongs_to :catalog_type
  has_many :catalog_entry_relationships

  validates :slug, presence: true, uniqueness: { scope: :catalog_type_id }
  validates :name, presence: true
  validates :attribute_type, presence: true, inclusion: { in: ATTRIBUTE_TYPES }
  validates :position, presence: true

  validate :slug_immutable, on: :update
  validate :attribute_type_immutable, on: :update
  validate :select_requires_options
  validate :reference_requires_type_id

  scope :ordered, -> { order(:position) }
  scope :reference_type, -> { where(attribute_type: TYPE_REFERENCE) }

  def reference? = attribute_type == TYPE_REFERENCE
  def select? = attribute_type == TYPE_SELECT

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
end
