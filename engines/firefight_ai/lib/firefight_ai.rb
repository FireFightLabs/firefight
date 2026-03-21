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
end
