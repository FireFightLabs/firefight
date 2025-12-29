class Workflow < ApplicationRecord
  include Workflow::Stateable
  include Workflow::Eventable
  include Workflow::Orchestratable
  include Workflow::Cancellable
  include Workflow::Pausable
  include Workflow::Metrics

  belongs_to :subject, polymorphic: true
  has_many :workflow_steps, -> { order(:position) }, dependent: :destroy
  has_many :workflow_events, dependent: :destroy

  validates :name, :workflow_class, :subject_type, :subject_id, :state, presence: true
  validate :workflow_class_must_exist
  validate :workflow_class_must_inherit_from_base

  def workflow_klass
    @workflow_klass ||= workflow_class.constantize
  end

  private

  def workflow_class_must_exist
    return if workflow_class.blank?

    workflow_class.constantize
  rescue NameError => e
    errors.add(:workflow_class, "must be a valid class name (#{workflow_class} not found)")
  end

  def workflow_class_must_inherit_from_base
    return if workflow_class.blank?

    klass = workflow_class.constantize
    unless klass < Workflows::Base
      errors.add(:workflow_class, "must inherit from Workflows::Base (#{workflow_class} does not)")
    end
  rescue NameError
    # Already handled by workflow_class_must_exist
  end
end
