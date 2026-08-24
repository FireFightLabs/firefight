# Usage counting and the *_blocked_reason rules, for any workspace-configurable
# list a settings screen manages. ConfigurableOption bundles this with
# positioning and the shared validations. Models with their own shape
# (custom fields keyed by `key`, runbooks with nested steps) include it alone.
module OptionGuards
  extend ActiveSupport::Concern

  class_methods do
    # The association that blocks deletion and drives the usage count.
    def usage_association
      :incidents
    end

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

  # Soft delete is a method, not a column callers write. Disabled rows stay
  # listed on the settings screen so an admin can enable them again.
  def disable!
    update!(deleted_at: Time.current)
  end

  def enable!
    update!(deleted_at: nil)
  end

  # Reads the count attached by with_usage_counts, falling back to a query so a
  # caller that forgot the scope gets a correct answer, not a permissive one.
  def usage_count
    has_attribute?(:usage_count) ? self[:usage_count].to_i : public_send(self.class.usage_association).count
  end

  def deletion_blocked_reason
    return unless usage_count.positive?

    "#{name} is in use by #{usage_count} #{usage_noun.pluralize(usage_count)} and cannot be deleted. Disable it instead."
  end

  def disable_blocked_reason
    nil
  end

  private

  def noun
    self.class::NOUN
  end

  # What the usage count counts, when it is not incidents.
  def usage_noun
    self.class.const_defined?(:USAGE_NOUN) ? self.class::USAGE_NOUN : "incident"
  end
end
