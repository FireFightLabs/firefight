class Runbook < ApplicationRecord
  include Positioned
  include OptionGuards

  NOUN = "runbook".freeze

  belongs_to :workspace

  has_many :runbook_steps, -> { order(:position) }, dependent: :destroy
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
    name.to_s.strip.downcase.gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
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

  def sync_steps!(steps_params)
    transaction do
      runbook_steps.destroy_all
      steps_params.each_with_index do |sp, index|
        runbook_steps.create!(
          title: sp[:title],
          instruction: sp[:instruction],
          position: index + 1
        )
      end
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
