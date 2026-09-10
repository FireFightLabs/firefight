# Usage counting and the *_blocked_reason rules. ConfigurableOption bundles
# this with positioning, models with their own shape include it alone.
module OptionGuards
  extend ActiveSupport::Concern

  class_methods do
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

  # Carries the sentence the surface shows, so a caller renders it without
  # knowing which rule refused.
  class Blocked < StandardError; end

  def disable!
    refuse!(disable_blocked_reason)
    update!(deleted_at: Time.current)
  end

  def enable!
    update!(deleted_at: nil)
  end

  # Falls back to a query so a caller that forgot with_usage_counts gets a
  # correct answer, not a permissive one.
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

  def refuse!(reason)
    raise Blocked, reason if reason
  end

  private

  def noun
    self.class::NOUN
  end

  def usage_noun
    self.class.const_defined?(:USAGE_NOUN) ? self.class::USAGE_NOUN : "incident"
  end
end
