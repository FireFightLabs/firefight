require "firefight_ai/providers/dialect"
require "firefight_ai/providers/regional"
require "firefight_ai/providers/zai"
require "firefight_ai/providers/minimax"
require "firefight_ai/providers/qwen"

module FirefightAi
  # Providers RubyLLM does not ship, each registered the way RubyLLM's custom provider guide says, with the models it
  # serves in providers/models.json. RubyLLM's published catalog holds none of them, so that file is where each model's
  # price, size and what it reads come from, every model citing the pages they were read from. A refresh writes the
  # file into the models table each night, so a change to it is used from the next refresh on.
  #
  # Each price is the highest the provider lists in US dollars, so a spend cap never counts a call as cheaper than it
  # was. For Qwen that is the Singapore and US price, above the global one. Z.AI's and MiniMax's China platforms charge
  # in yuan, so theirs is the international price.
  module Providers
    MODELS = File.expand_path("providers/models.json", __dir__)

    ALL = { zai: Zai, minimax: Minimax, qwen: Qwen }.freeze

    ALL.each { |slug, provider| RubyLLM::Provider.register(slug, provider, models: MODELS) }
  end
end
