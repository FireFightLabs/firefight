# Waits a duration, or until a time of day in a time zone, run by the engine. Nothing is held while it waits.
class DefinedWorkflow::Steps::Delay < DefinedWorkflow::Steps::Base
  kind DefinedWorkflow::KIND_DELAY
  label "Delay"
  group GROUP_WAITING

  def self.engine? = true

  def self.problems(_step, _workspace) = []

  def self.output_fields(_config) = SolidWorkflow::Definition::OUTPUT_FIELDS.fetch(DefinedWorkflow::KIND_DELAY)

  def self.describe(config, _workspace)
    return "until #{config['until']} (#{config['time_zone'].presence || 'UTC'})" if config["until"].present?
    return "until #{config['at']}" if config["at"].present?

    SolidWorkflow::Definition::DELAY_UNITS.keys.filter_map { |unit| "#{config[unit]} #{unit}" if config[unit].present? }.join(" ")
  end
end
