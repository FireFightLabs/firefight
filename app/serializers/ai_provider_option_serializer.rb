# A provider a workspace can add as its own AI account, with what the form asks for and the models it suggests.
class AiProviderOptionSerializer < BaseSerializer
  object_as :provider

  attributes(slug: { type: :string }, name: { type: :string })

  type :string, optional: true
  def main_model = provider.main_model

  type :string, optional: true
  def fast_model = provider.fast_model

  # Empty when the provider's models are the customer's own names, which the form then takes as typed.
  type "string[]"
  def chat_models = provider.chat_models

  type "{ key: string; label: string; secret: boolean; required: boolean }[]"
  def fields = provider.fields.map { |field| { key: field.key, label: field.label, secret: field.secret, required: field.required } }

  # Whether a code fix can run on this provider's models.
  type :boolean
  def code_fixes = provider.code_fixes
end
