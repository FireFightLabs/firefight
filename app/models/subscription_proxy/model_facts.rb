module SubscriptionProxy
  # What the engine is told of a model a workspace's subscription serves, which RubyLLM's registry cannot hold since its
  # name carries the workspace's prefix. Read from what the proxy last listed for the workspace's subscriptions.
  module ModelFacts
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    def self.for(model, provider)
      return nil unless provider == AiProviders::SUBSCRIPTION_PROXY

      workspace_id, name = model.split("/", 2)
      return nil unless name.present? && workspace_id.match?(UUID)

      WorkspaceAiAccount.subscriptions.where(workspace_id: workspace_id).find_each do |account|
        known = account.proxy_models.find { |entry| entry["id"] == name }
        return facts(known) if known
      end
      nil
    end

    def self.facts(entry)
      FirefightAi::ModelFacts.new(name: entry["name"].presence, context_window: entry["context_window"].to_i,
                                  max_output_tokens: entry["max_output_tokens"].to_i, input_modalities: Array(entry["input_modalities"]))
    end
    private_class_method :facts
  end
end
