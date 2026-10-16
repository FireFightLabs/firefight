# A trigger input marked private, such as a check's notes, whose value names systems and thresholds and so is kept like
# instructions are, encrypted and never in the trigger, an edit, a run's inputs, a step's data or the engine's context.
# Each version keeps the values its trigger asks with, so a draft's change waits for publishing like the rest of it, and a
# run keeps the value it was started with. Everywhere else a private input reads as its token, and only a Halon step,
# whose words are kept encrypted too, is handed the value, in memory, just before it asks the model.
module Workflow::PrivateInputs
  extend ActiveSupport::Concern

  included do
    encrypts :private_inputs
  end

  # The values kept for its private inputs, by key.
  def private_input_values = private_inputs.present? ? JSON.parse(private_inputs) : {}

  # The values kept with values laid over them, as they are stored.
  def private_inputs_with(values) = private_input_values.merge(values.to_h.stringify_keys).to_json

  # The same for a guarded update_all that saves it with the change it belongs to, or nothing when there are no values.
  # update_all encrypts it as save does.
  def private_inputs_column_with(values)
    return {} if values.blank?

    { private_inputs: private_inputs_with(values) }
  end

  # The same for a change to trigger, which keeps only the values of inputs it still marks private, or nothing when that
  # leaves them as they are.
  def private_inputs_column_for(trigger, values)
    kept = private_input_values.merge(values.to_h.stringify_keys).slice(*Workflow::Trigger.private_keys(trigger))
    kept == private_input_values ? {} : { private_inputs: kept.presence&.to_json }
  end

  def keep_private_inputs!(values)
    return if values.blank?

    update!(private_inputs: private_inputs_with(values))
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
end
