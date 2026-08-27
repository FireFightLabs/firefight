# For option lists where exactly one row is the workspace default. The default
# cannot be deleted or disabled, and a disabled row cannot be promoted.
module DefaultableOption
  extend ActiveSupport::Concern

  included do
    validates :is_default, uniqueness: { scope: :workspace_id, if: :is_default? }
  end

  class_methods do
    def defaultable?
      true
    end
  end

  # Promoting one demotes the incumbent in the same transaction. A partial
  # unique index backs this up, since the model validation alone cannot stop an
  # update_all or a raw write.
  def make_default!
    refuse!(default_blocked_reason)

    self.class.transaction do
      self.class.where(workspace_id: workspace_id, is_default: true).where.not(id: id).update_all(is_default: false)
      update!(is_default: true)
    end
  end

  def deletion_blocked_reason
    return "#{name} is the default #{noun}. Make another #{noun} the default before deleting it." if is_default?

    super
  end

  def disable_blocked_reason
    return "#{name} is the default #{noun} and has to stay enabled. Make another #{noun} the default first." if is_default?

    super
  end

  def default_blocked_reason
    return "#{name} is disabled. Enable it before making it the default." unless enabled?

    super
  end
end
