# A tool a runbook step can be run with, as the editor offers it: the name Halon calls it, the group a person finds it
# under, and a field for each of its parameters.
class RunbookToolChoiceSerializer < BaseSerializer
  object_as :choice

  type :string
  def name
    choice.name
  end

  type :string
  def group
    choice.group
  end

  type :string
  def description
    choice.description
  end

  type "{ key: string; kind: #{Chat::Tools::Choices::KINDS.map(&:inspect).join(' | ')}; options: string[]; required: boolean; description: string | null }[]"
  def fields
    choice.fields.map { |field| { key: field.key, kind: field.kind, options: field.options, required: field.required, description: field.description } }
  end
end
