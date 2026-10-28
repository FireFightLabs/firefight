module FirefightAi
  module Providers
    # Z.AI's pay-as-you-go API, at api.z.ai, and the same API as Zhipu's BigModel serves it in China, where a key made on
    # one does not work on the other (docs.z.ai/guides/overview/quick-start, docs.bigmodel.cn/cn/guide/start/quick-start).
    # The GLM Coding Plan has keys and addresses of its own and is for coding tools only, so it is not offered. Its JSON
    # mode is json_object, with the schema asked for in words (docs.z.ai/guides/capabilities/struct-output).
    class Zai < Regional
      class ChatCompletions < RubyLLM::Protocols::ChatCompletions
        include Dialect
      end

      protocol :chat_completions, ChatCompletions

      class << self
        def addresses = { "global" => "https://api.z.ai/api/paas/v4", "china" => "https://open.bigmodel.cn/api/paas/v4" }

        def display_name = "Z.AI"

        def configuration_options = %i[zai_api_key zai_region]

        def configuration_requirements = %i[zai_api_key zai_region]
      end
    end
  end
end
