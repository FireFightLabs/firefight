module FirefightAi
  module Providers
    # Qwen through its OpenAI compatible API, sold two ways. QwenCloud (home.qwencloud.com) serves each of its six
    # regions at {region}.maas.qwencloudapi.com (docs.qwencloud.com/developer-guides/getting-started/regions). Alibaba
    # Cloud Model Studio serves four regions at an address every workspace shares, and Frankfurt and Tokyo only at one
    # named for the workspace (alibabacloud.com/help/en/model-studio/base-url). Neither says the other's keys work on
    # its addresses, and every key works only in the region it was made in, so each region of each is its own choice.
    # The Coding Plan and Token Plan have keys and addresses of their own and are not offered.
    #
    # Its JSON mode is json_object, and json_schema is not served in Singapore, so the schema is asked for in words
    # everywhere. JSON mode does not run while the model thinks, so a call asking for JSON turns thinking off
    # (alibabacloud.com/help/en/model-studio/qwen-structured-output and deep-thinking).
    class Qwen < Regional
      WORKSPACE_ID = "workspace_id".freeze
      QWENCLOUD_REGIONS = %w[ap-southeast-1 us-east-1 eu-central-1 ap-northeast-1 cn-hongkong cn-beijing].freeze
      MODEL_STUDIO = "alibaba-".freeze
      MODEL_STUDIO_SHARED = {
        "alibaba-ap-southeast-1" => "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        "alibaba-us-east-1" => "https://dashscope-us.aliyuncs.com/compatible-mode/v1",
        "alibaba-cn-hongkong" => "https://cn-hongkong.dashscope.aliyuncs.com/compatible-mode/v1",
        "alibaba-cn-beijing" => "https://dashscope.aliyuncs.com/compatible-mode/v1"
      }.freeze
      # Model Studio regions whose only address carries the workspace's ID.
      MODEL_STUDIO_WORKSPACE = %w[alibaba-eu-central-1 alibaba-ap-northeast-1].freeze

      class ChatCompletions < RubyLLM::Protocols::ChatCompletions
        include Dialect

        def render_payload(messages, schema: nil, **)
          payload = super(messages, schema:, **)
          payload[:enable_thinking] = false if schema
          payload
        end

        # The model reads past reasoning only with preserve_thinking, which bills it again as input, so only answers go back.
        def format_thinking(_msg) = {}
      end

      protocol :chat_completions, ChatCompletions

      class << self
        def addresses
          QWENCLOUD_REGIONS.index_with { |region| "https://#{region}.maas.qwencloudapi.com/compatible-mode/v1" }.merge(MODEL_STUDIO_SHARED)
        end

        def regions = addresses.keys.index_with { [] }.merge(MODEL_STUDIO_WORKSPACE.index_with { [ WORKSPACE_ID ] })

        def address(config)
          region = setting(config, :region)
          return super unless MODEL_STUDIO_WORKSPACE.include?(region)

          workspace = setting(config, :workspace_id)
          "https://#{workspace}.#{region.delete_prefix(MODEL_STUDIO)}.maas.aliyuncs.com/compatible-mode/v1" if workspace.match?(/\A[a-z0-9-]+\z/i)
        end

        def display_name = "Qwen"

        def configuration_options = %i[qwen_api_key qwen_region qwen_workspace_id]

        def configuration_requirements = %i[qwen_api_key qwen_region]
      end
    end
  end
end
