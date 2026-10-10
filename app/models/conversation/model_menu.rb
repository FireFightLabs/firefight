# The models a person can switch a dashboard chat to, which are the workspace's main model and the ones listed for its
# provider (config/ai_providers.yml, chat_models). A pick runs on the same account and payer as the main model, so
# switching never changes who pays. The house's keys offer a pick only on a provider the deployment holds a key for.
class Conversation::ModelMenu
  Option = Data.define(:model, :label, :note, :default, :reads_images)

  NOT_OFFERED = "That model is not one this workspace's AI account can run. Pick another.".freeze
  DEFAULT_NOTE = "This workspace's main model".freeze

  def self.for(workspace) = new(FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: workspace))

  # What a reply calls the model that wrote it, by the picker's name, else the registry's, else the id.
  def self.label(model, provider:)
    AiProviders.chat_model_label(provider, model) || FirefightAi.model_name(model, provider: provider) || model.to_s
  end

  def initialize(main)
    @main = main
  end

  def default_model = @main.model

  def models = @models ||= build_models

  # One model leaves nothing to switch to, so the picker is not shown.
  def offers_choice? = models.size > 1

  def offered?(model) = models.any? { |option| option.model == model.to_s }

  def blocked_reason(model) = (NOT_OFFERED unless offered?(model))

  # What a chat with this pick runs on, or nil when the pick is the main model or no longer offered.
  def choice(model)
    return nil if model.to_s == default_model || !offered?(model)

    @main.with(model: model.to_s, provider: provider)
  end

  # The model a chat with this pick runs on now.
  def current(model) = offered?(model) ? model.to_s : default_model

  def label_for(model) = models.find { |option| option.model == model.to_s }&.label || self.class.label(model, provider: provider)

  private

  def provider = @provider ||= @main.provider_name.to_s

  def build_models
    return [] if @main.unpaid?

    listed = reachable? ? AiProviders.chat_models(provider) : []
    offered = listed.map { |entry| option(entry.model, entry.label, entry.note) }
    return offered if listed.any? { |entry| entry.model == default_model }

    [ option(default_model, self.class.label(default_model, provider: provider), DEFAULT_NOTE), *offered ]
  end

  def option(model, label, note)
    Option.new(model: model, label: label, note: note, default: model == default_model,
               reads_images: FirefightAi.input_modalities(model, provider: provider).include?(Chat::Attachment::KIND_IMAGE))
  end

  # A workspace's own account runs what its provider serves. The house needs a key of its own for the provider.
  def reachable?
    return true if @main.own_account?

    AiProviders.find(provider)&.configured?(RubyLLM.config) || false
  end
end
