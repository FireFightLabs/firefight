class IncidentFieldOption < ApplicationRecord
  # Slack caps a plain_text option label at 75 characters and fails the whole
  # views.open when one is longer, so the limit is enforced at the source.
  MAX_LABEL_LENGTH = 75

  belongs_to :incident_field_definition
  has_many :incident_field_values, dependent: :restrict_with_error

  validates :label, presence: true, length: { maximum: MAX_LABEL_LENGTH }
  validates :label, uniqueness: {
    scope: :incident_field_definition_id,
    conditions: -> { where(disabled_at: nil) }
  }, if: :enabled?
  validates :position, presence: true

  scope :active, -> { where(disabled_at: nil) }
  scope :ordered, -> { order(:position, :created_at) }

  # Two queries for any number of definitions, tallied in Ruby, so a settings
  # screen listing N fields does not pay 2N.
  def self.usage_counts_for(definitions)
    definitions = Array.wrap(definitions)
    return {} if definitions.empty?

    option_ids = where(incident_field_definition_id: definitions.map(&:id)).pluck(:id)
    return {} if option_ids.empty?

    counts = IncidentFieldValue
      .where(incident_field_option_id: option_ids)
      .group(:incident_field_option_id)
      .count

    known = option_ids.to_set

    IncidentCondition
      .where(incident_field_definition_id: definitions.map(&:id))
      .pluck(:values)
      .flatten
      .tally
      .each do |option_id, n|
        next unless known.include?(option_id)
        counts[option_id] = counts.fetch(option_id, 0) + n
      end

    counts
  end

  # Attaches counts to a whole list of definitions at once, so each option can
  # answer deletion_blocked_reason without going back to the database.
  def self.preload_usage_counts(definitions)
    counts = usage_counts_for(definitions)

    definitions.each do |definition|
      definition.incident_field_options.each do |option|
        option.usage_count = counts.fetch(option.id, 0)
      end
    end

    definitions
  end

  def enabled?
    disabled_at.nil?
  end

  def usage_count
    @usage_count ||= IncidentFieldOption.usage_counts_for(incident_field_definition).fetch(id, 0)
  end

  # Set by the definition when it loads a whole option list, so a settings
  # screen does not pay a query per row.
  attr_writer :usage_count

  def deletion_blocked_reason
    return if usage_count.zero?

    "#{label} is in use by #{usage_count} #{'reference'.pluralize(usage_count)} " \
      "and cannot be deleted. Disable it instead."
  end

  def disable_blocked_reason
    nil
  end
end
