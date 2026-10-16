# What a runbook ran before it linked a workflow: steps that name a tool, inputs such as {{bump}} and a watch. Each moves
# into the linked workflow (Runbook::LinkedWorkflow), so a runbook keeps them only when moving them was refused, and they
# stay well formed until then. Its other names are how a person asks for it.
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
    def placeholders_in(value) = Placeholders.references_in(value, PLACEHOLDER)
  end

  def input_keys = inputs.map { |input| input["key"] }

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
      return errors.add(:watch, "Watch needs steps, each naming the capability to check and the resource, or a read tool")
    end

    steps.each_with_index { |step, index| watch_step_well_formed(step, index) }
  end

  # A step reads with a capability on a resource, or with any read tool Halon can make in a chat, by its name and arguments.
  # Whether the tool reads, and what it answers, is checked when the watch starts, as the person it runs for.
  def watch_step_well_formed(step, index)
    keys = Chat::Watch::SPEC_KEYS
    tool = step[keys[:tool]]
    if tool.present?
      return errors.add(:watch, "Watch #{item_name(step, index)}: needs the read tool's name as Halon calls it") unless tool.to_s.match?(RunbookStep::TOOL_NAME)
      return errors.add(:watch, "Watch #{item_name(step, index)}: needs the tool's arguments as an object") unless step.fetch(keys[:arguments], {}).is_a?(Hash)
    elsif step[keys[:capability]].blank? || step[keys[:resource]].blank?
      return errors.add(:watch, "Watch #{item_name(step, index)}: needs the capability to check and the resource, or a read tool")
    end

    errors.add(:watch, "Watch #{item_name(step, index)}: needs what counts as done (done when, failed when or a goal)") if Chat::Watch::Step.undecided?(step)
    watch_order_well_formed(step, index)
    new_deploy = step[keys[:new_deploy]]
    return if new_deploy.nil? || (new_deploy.is_a?(Hash) && new_deploy.values.all? { |value| value.is_a?(String) })

    errors.add(:watch, "Watch #{item_name(step, index)}: needs the new deploy it waits for as words, such as a commit, a tag or a branch")
  end

  # An item waits only for items before it, named by their names or their numbers as the settings page numbers them.
  def watch_order_well_formed(step, index)
    order = step[Chat::Watch::SPEC_KEYS[:waits_for]]
    return if order.nil?
    unless order.is_a?(Array) && order.all? { |ref| ref.is_a?(String) || ref.is_a?(Integer) }
      return errors.add(:watch, "Watch #{item_name(step, index)}: needs the items it waits for as a list of their names or numbers")
    end

    labels = watch["steps"].map { |each| each[Chat::Watch::SPEC_KEYS[:label]].to_s.squish }
    order.each do |ref|
      at = Chat::Watch::Step.position_named(ref, labels)
      next errors.add(:watch, "Watch #{item_name(step, index)}: waits for #{ref}, which is not one of its items") if at.nil?
      next if at < index

      errors.add(:watch, "Watch #{item_name(step, index)}: waits for #{ref}, which does not come before it, and an item waits only for items before it")
    end
  end

  # An error names a watch item by its name, or by its number as the settings page numbers them when it has none.
  # Each watch error is a whole sentence (config/locales/en.yml), so every surface shows it the same.
  def item_name(step, index)
    label = step[Chat::Watch::SPEC_KEYS[:label]].to_s.squish
    label.present? ? "'#{label}'" : (index + 1).to_s
  end
end
