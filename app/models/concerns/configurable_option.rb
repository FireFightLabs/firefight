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

    belongs_to :workspace

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :workspace_id }
    validates :position, presence: true, numericality: { only_integer: true }

    scope :active, -> { where(deleted_at: nil) }
    scope :ordered, -> { order(:position) }
  end

  class_methods do
    # The association that blocks deletion and drives the usage count.
    def usage_association
      :incidents
    end

    def defaultable?
      false
    end

    def colored?
      column_names.include?("color")
    end

    # One correlated subquery for the page rather than a count per row.
    def with_usage_counts
      reflection = reflect_on_association(usage_association)

      select(
        "#{table_name}.*",
        "(SELECT COUNT(*) FROM #{reflection.table_name}" \
        " WHERE #{reflection.table_name}.#{reflection.foreign_key} = #{table_name}.id) AS usage_count"
      )
    end
  end

  def enabled?
    deleted_at.nil?
  end

  # Reads the count attached by with_usage_counts, falling back to a query so a
  # caller that forgot the scope gets a correct answer, not a permissive one.
  def usage_count
    has_attribute?(:usage_count) ? self[:usage_count].to_i : public_send(self.class.usage_association).count
  end

  def deletion_blocked_reason
    return unless usage_count.positive?

    "#{name} is in use by #{usage_count} #{'incident'.pluralize(usage_count)} and cannot be deleted. Disable it instead."
  end

  def disable_blocked_reason
    nil
  end

  def default_blocked_reason
    nil
  end

  private

  def noun
    self.class::NOUN
  end
end
