# The option lists a settings screen manages. The *_blocked_reason methods
# are the only place their rules live, every layer renders the sentence.
module ConfigurableOption
  extend ActiveSupport::Concern

  # The API answers it as a bad request and MCP as the tool error.
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
    # Renumbered as part of the write, so no caller has to remember to.
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

  # 1 is first. A position past either end lands on that end, so "put it
  # last" needs no count. Mirrored columns such as rank follow from the reorder.
  def place_at!(position)
    target = Integer(position, exception: false)
    raise InvalidPosition, "position must be a whole number, 1 being first" if target.nil?

    ids = self.class.list_for(workspace).ordered.pluck(:id) - [ id ]
    ids.insert(target.clamp(1, ids.size + 1) - 1, id)
    self.class.reorder!(workspace, ids)
    reload
  end

  private

  # The dialog only shows errors on the field typed, so a slug collision must
  # be reported on name or the dialog stays open saying nothing.
  def name_produces_a_free_slug
    return unless errors.of_kind?(:slug, :taken)

    errors.add(:name, "is already used by another #{self.class::NOUN}.")
  end
end
