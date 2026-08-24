class Runbook < ApplicationRecord
  include Positioned
  include OptionGuards

  NOUN = "runbook".freeze

  belongs_to :workspace

  has_many :runbook_steps, -> { active.ordered }
  has_many :all_runbook_steps, class_name: "RunbookStep", dependent: :destroy
  has_many :incident_conditions, as: :conditionable, dependent: :destroy
  has_many :incident_runbooks, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id, conditions: -> { where(deleted_at: nil) } }
  validates :position, presence: true

  before_validation :assign_slug, on: :create
  before_validation :assign_position, on: :create

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position) }

  def self.usage_association
    :incident_runbooks
  end

  def self.generate_slug(name)
    Sluggable.word_slug(name)
  end

  # No conditions means no automatic attachment, because a runbook that lands
  # on every incident should be a decision rather than the consequence of
  # leaving a form empty. Reaching every incident is what always_attach is for.
  def self.matching(workspace, context)
    workspace.runbooks.active.ordered.includes(incident_conditions: :incident_field_definition).select do |runbook|
      next runbook.always_attach? if runbook.incident_conditions.empty?

      IncidentConditionEvaluator.match?(runbook.incident_conditions, context)
    end
  end

  # Steps keep their identity across edits. Incident actions reference a step
  # by id, so recreating the rows on every save would unclaim every step in
  # every live incident. A step missing from the payload is soft-deleted, which
  # keeps the actions that already point at it readable.
  def sync_steps!(steps_params)
    transaction do
      live = runbook_steps.index_by(&:id)
      kept_ids = []

      steps_params.each_with_index do |step_params, index|
        attrs = { title: step_params[:title], instruction: step_params[:instruction], position: index + 1 }
        step = live[step_params[:id].to_s]

        if step
          step.update!(attrs)
        else
          step = all_runbook_steps.create!(attrs)
        end

        kept_ids << step.id
      end

      now = Time.current
      live.each_value { |step| step.update!(deleted_at: now) unless kept_ids.include?(step.id) }
      runbook_steps.reset
    end
  end

  def sync_conditions!(conditions_params)
    transaction do
      incident_conditions.destroy_all
      conditions_params.each do |cp|
        incident_conditions.create!(
          workspace: workspace,
          condition_field: cp[:condition_field],
          operator: cp[:operator],
          values: cp[:values],
          incident_field_definition_id: cp[:incident_field_definition_id]
        )
      end
    end
  end

  private

  def assign_slug
    self.slug = self.class.generate_slug(name) if slug.blank?
  end

  def assign_position
    self.position ||= workspace.runbooks.maximum(:position).to_i + 1
  end
end
