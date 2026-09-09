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

  # Raised by place_at! for a position that is not a whole number. The API
  # answers it as a bad request and MCP as the tool error.
  class InvalidPosition < ArgumentError; end

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
    def create_in_list!(workspace, attributes, position: nil)
      option = list_for(workspace).new(**attributes)
      option.save_in_position!
      renumber!(workspace)
      position.present? ? option.place_at!(position) : option
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

  def config_extras
    {}
  end

  def destroy_from_list!
    refuse!(deletion_blocked_reason)
    destroy!
    self.class.renumber!(workspace)
  end

  # Moves this row to the given position, 1 being first, and renumbers the
  # rest around it through the same reorder the settings screen drags run.
  # A position past either end lands on that end, so "put it first" and "put
  # it last" need no count first. Mirrored columns such as a severity's rank
  # follow, because the reorder derives them from the final order.
  def place_at!(position)
    target = Integer(position, exception: false)
    raise InvalidPosition, "position must be a whole number, 1 being first" if target.nil?

    ids = self.class.list_for(workspace).ordered.pluck(:id) - [ id ]
    ids.insert(target.clamp(1, ids.size + 1) - 1, id)
    self.class.reorder!(workspace, ids)
    reload
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
