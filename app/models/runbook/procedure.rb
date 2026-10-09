# A runbook Halon can run. Its steps may each name a tool, by the name Halon calls it, with the arguments to call it with,
# and any of those values may hold an input such as {{bump}}, asked of the person when it runs or taken from its default.
# The watch is what to follow once every step went through, a start_watch request with the same inputs filled in. A
# runbook without any of this is a plain incident runbook and behaves exactly as one.
module Runbook::Procedure
  extend ActiveSupport::Concern

  INPUT_KEY = /\A[a-z][a-z0-9_]*\z/
  PLACEHOLDER = /\{\{\s*([a-z][a-z0-9_]*)\s*\}\}/
  INPUT_FIELDS = %w[key question default].freeze
  ALIAS_LIMIT = 10
  INPUT_LIMIT = 10

  included do
    before_validation :tidy_procedure
    validate :inputs_well_formed
    validate :watch_well_formed
  end

  class_methods do
    # The runbook a person named, by its slug, its name or one of its other names, whatever the case.
    def named(scope, text)
      wanted = text.to_s.squish.downcase
      return if wanted.empty?

      scope.find_by(slug: wanted) || scope.find_by("LOWER(runbooks.name) = ?", wanted) ||
        scope.find_by("EXISTS (SELECT 1 FROM unnest(runbooks.aliases) AS other WHERE LOWER(other) = ?)", wanted)
    end

    # Every input a value names, in the order they first appear.
    def placeholders_in(value)
      case value
      when String then value.scan(PLACEHOLDER).flatten
      when Hash then value.values.flat_map { |inner| placeholders_in(inner) }
      when Array then value.flat_map { |inner| placeholders_in(inner) }
      else []
      end.uniq
    end

    # The value with each input put in its place. A value that is only one input keeps the input's own type.
    def filled(value, inputs)
      case value
      when String
        whole = value.match(/\A#{PLACEHOLDER}\z/)
        whole ? inputs.fetch(whole[1], value) : value.gsub(PLACEHOLDER) { inputs.fetch(Regexp.last_match(1), Regexp.last_match(0)).to_s }
      when Hash then value.transform_values { |inner| filled(inner, inputs) }
      when Array then value.map { |inner| filled(inner, inputs) }
      else value
      end
    end
  end

  # Whether Halon can run it, because a step names a tool or there is something to watch.
  def procedure? = runbook_steps.any?(&:tool?) || watch.present?

  def input_keys = inputs.map { |input| input["key"] }

  # What the person gave, with each input they left out taken from its default. missing names those with neither.
  Resolved = Data.define(:values, :missing)

  def resolve_inputs(given)
    given = given.to_h.stringify_keys.transform_values { |value| value.is_a?(String) ? value.strip : value }
    values = inputs.to_h { |input| [ input["key"], given[input["key"]].presence || input["default"].presence ] }
    Resolved.new(values: values.compact, missing: inputs.reject { |input| values[input["key"]].present? })
  end

  # The watch to start, with its inputs filled in and each item with no name named after what it reads. A read tool is
  # named as tool_title calls it.
  def filled_watch(values, &tool_title)
    return if watch.blank?

    filled = self.class.filled(watch, values)
    label = Chat::Watch::SPEC_KEYS[:label]
    steps = Array(filled["steps"]).map do |step|
      named = step[label].to_s.strip.present? ? nil : Chat::Watch::Step.default_label(step, &tool_title)
      named ? step.merge(label => named) : step
    end
    filled.merge("steps" => steps)
  end

  private

  def tidy_procedure
    self.aliases = Array(aliases).map { |other| other.to_s.squish }.compact_blank.uniq(&:downcase).first(ALIAS_LIMIT)
    self.inputs = Array(inputs).map { |input| input.to_h.stringify_keys.slice(*INPUT_FIELDS).transform_values { |value| value.to_s.strip } }
    self.watch = watch.blank? ? nil : watch.deep_stringify_keys
  end

  def inputs_well_formed
    errors.add(:inputs, "can be at most #{INPUT_LIMIT}") if inputs.size > INPUT_LIMIT
    inputs.each do |input|
      next errors.add(:inputs, "need keys of lowercase letters, numbers and underscores, such as bump") unless input["key"].to_s.match?(INPUT_KEY)

      errors.add(:inputs, "need a question for #{input['key']}") if input["question"].blank?
    end
    errors.add(:inputs, "must each have a key of their own") unless input_keys.uniq.size == input_keys.size
    unknown = self.class.placeholders_in(watch) - input_keys
    errors.add(:watch, "Watch uses #{unknown.map { |key| "{{#{key}}}" }.to_sentence}, which is not one of its inputs") if unknown.any?
  end

  def watch_well_formed
    return if watch.nil?

    steps = watch.is_a?(Hash) ? watch["steps"] : nil
    unless steps.is_a?(Array) && steps.any? && steps.all? { |step| step.is_a?(Hash) }
      return errors.add(:watch, "Watch needs steps, each naming the capability to check and the resource")
    end

    steps.each_with_index do |step, index|
      if step["capability"].blank? || step["resource"].blank?
        errors.add(:watch, "Watch #{item_name(step, index)}: needs the capability to check and the resource")
      elsif Chat::Watch::Step.undecided?(step)
        errors.add(:watch, "Watch #{item_name(step, index)}: needs what counts as done (done when, failed when or a goal)")
      end
    end
  end

  # An error names a watch item by its name, or by its number as the settings page numbers them when it has none.
  # Each watch error is a whole sentence (config/locales/en.yml), so every surface shows it the same.
  def item_name(step, index)
    label = step[Chat::Watch::SPEC_KEYS[:label]].to_s.squish
    label.present? ? "'#{label}'" : (index + 1).to_s
  end
end
