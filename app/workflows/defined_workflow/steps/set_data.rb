# Names values for later steps, or picks what they need out of bigger data. Each value is text that may hold references,
# and one that is only a reference keeps its type, so a list or an object passes on whole. Text written as a JSON object
# or list becomes that object or list once its references are filled, which is how data is reshaped. It reads only the
# run's own data.
class DefinedWorkflow::Steps::SetData < DefinedWorkflow::Steps::Base
  kind "set_data"
  label "Set data"
  group GROUP_CONTROL

  KEY_VALUES = "values".freeze
  VALUE_NAME = "name".freeze
  VALUE_VALUE = "value".freeze
  VALUE_LIMIT = 20

  config_help "values (a list of up to #{VALUE_LIMIT} {name, value}, each name lowercase with underscores, each value text that may use " \
              "references, a lone reference keeping its type, and text written as a JSON object or list becoming one). Outputs each name."

  class << self
    def entries(config) = Array(config[KEY_VALUES]).select { |entry| entry.is_a?(Hash) }

    def output_fields(config) = entries(config).filter_map { |entry| entry[VALUE_NAME].to_s.presence }.uniq

    def problems(step, _workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      names = entries(config).map { |entry| entry[VALUE_NAME].to_s }
      found = []
      found << "#{named} needs at least one value to name." if names.empty?
      found << "#{named} names at most #{VALUE_LIMIT} values." if names.size > VALUE_LIMIT
      found << "#{named} needs each value named in lowercase letters, numbers and underscores." unless names.all? { |name| name.match?(SolidWorkflow::Definition::STEP_NAME) }
      duplicates = names.tally.select { |_name, count| count > 1 }.keys
      found << "#{named} names #{duplicates.to_sentence} more than once." if duplicates.any?
      found
    end

    def describe(config, _workspace) = "Names #{output_fields(config).join(', ')}".truncate(200)
  end

  def perform = self.class.entries(@config).to_h { |entry| [ entry[VALUE_NAME].to_s, shaped(entry[VALUE_VALUE]) ] }

  private

  def shaped(value)
    return value unless value.is_a?(String) && value.strip.start_with?("{", "[")

    JSON.parse(value)
  rescue JSON::ParserError
    value
  end
end
