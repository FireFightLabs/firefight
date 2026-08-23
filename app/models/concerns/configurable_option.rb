# Shared behaviour for the workspace-configurable option lists a settings screen
# manages: severities, statuses, incident types, incident roles. Each is
# positioned, soft disableable, and refuses deletion while something points at
# it.
#
# The *_blocked_reason methods are the single source of truth for those rules.
# The controller turns a reason into a flash alert, the serializer ships it, and
# the row renders it as a tooltip, so a rule is written once rather than once
# per layer.
module ConfigurableOption
  extend ActiveSupport::Concern

  included do
    include Positioned
    include OptionGuards
    include NormalizedDescription
    include Sluggable

    belongs_to :workspace

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :workspace_id }
    validates :position, presence: true, numericality: { only_integer: true }
    validate :name_produces_a_free_slug

    scope :active, -> { where(deleted_at: nil) }
    scope :ordered, -> { order(:position) }
  end

  class_methods do
    def defaultable?
      false
    end

    def colored?
      column_names.include?("color")
    end
  end

  def default_blocked_reason
    nil
  end

  private

  # The slug is derived from the name and the dialog only shows errors on the
  # field the user typed, so a slug collision has to be reported on name or
  # the dialog stays open saying nothing.
  def name_produces_a_free_slug
    return unless errors.of_kind?(:slug, :taken)

    errors.add(:name, "is already used by another #{self.class::NOUN}.")
  end
end
