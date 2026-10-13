# A trigger input marked private, such as a check's notes, whose value names systems and thresholds and so is kept like
# instructions are: encrypted, and never in the trigger, an edit, a run's inputs, a step's data or the engine's context.
# The workflow keeps the value it runs with, and a run keeps the value it was started with. Everywhere else a private
# input reads as its token, and only a Halon step, whose words are kept encrypted too, is handed the value, in memory,
# just before it asks the model.
module Workflow::PrivateInputs
  extend ActiveSupport::Concern

  included do
    encrypts :private_inputs
  end

  # The values kept for its private inputs, by key.
  def private_input_values = private_inputs.present? ? JSON.parse(private_inputs) : {}

  def keep_private_inputs!(values)
    return if values.blank?

    update!(private_inputs: private_input_values.merge(values.to_h.stringify_keys).to_json)
  end

  # value with every private input's token put back as its value, for a Halon step about to ask the model.
  def unsealed(value)
    values = private_input_values
    return value if values.empty?

    tokens = values.to_h { |key, kept| [ Workflow::Trigger.private_token(key), kept.to_s ] }
    replace = lambda do |inner|
      case inner
      when String then tokens.reduce(inner) { |text, (token, kept)| text.gsub(token, kept) }
      when Hash then inner.transform_values { |each| replace.call(each) }
      when Array then inner.map { |each| replace.call(each) }
      else inner
      end
    end
    replace.call(value)
  end

  # A trigger with its private inputs' values taken out and kept here. Returns the trigger as it is stored.
  def seal_trigger!(trigger)
    stripped, values = Workflow::Trigger.sealed(trigger)
    keep_private_inputs!(values)
    stripped
  end
end
