require "ruby_llm"
require "ruby_llm/schema"
require "firefight_ai/version"
require "firefight_ai/configuration"
require "firefight_ai/engine"

module FirefightAi
  extend self

  def configuration
    @configuration ||= Configuration.new
  end

  def configure
    yield configuration
  end

  # Every service resolves its model here: the feature's own override wins,
  # then the configured workspace-wide default, then the feature's fallback.
  def model_for(feature_env_var, fallback)
    ENV[feature_env_var].presence || configuration.default_model.presence || fallback
  end
end
