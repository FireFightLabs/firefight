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

    belongs_to :workspace

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :workspace_id }
    validates :position, presence: true, numericality: { only_integer: true }

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
end
