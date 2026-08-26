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
    # Creating or deleting leaves the position sequence with a gap or a
    # collision, so the list is renumbered as part of the write rather than by
    # whoever remembered to. Every surface that manages one of these lists
    # calls these two.
    def create_in_list!(workspace, attributes)
      option = list_for(workspace).new(**attributes)
      option.save_in_position!
      renumber!(workspace)
      option
    end

    def renumber!(workspace)
      reorder!(workspace, list_for(workspace).ordered.pluck(:id))
    end

    def list_for(workspace)
      where(workspace_id: workspace.id)
    end

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

  # What this list has beyond the shared shape, for a surface reporting one
  # back. Empty for every list that has nothing extra.
  def config_extras
    {}
  end

  def destroy_from_list!
    refuse!(deletion_blocked_reason)
    destroy!
    self.class.renumber!(workspace)
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
