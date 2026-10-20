require "test_helper"
require Rails.root.join("db/migrate/20261020180000_move_deepseek_v4_flash_choices_to_v4_1_flash")

class MoveDeepseekV4FlashChoicesToV41FlashTest < ActiveSupport::TestCase
  include AiAccountTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    member = workspace_memberships(:alice_workspace_one)
    @direct_chat = Conversation.start_personal!(workspace: @workspace, member: member)
    @direct_chat.update_columns(chosen_model: "deepseek-v4-flash")
    @openrouter_chat = Conversation.start_personal!(workspace: @workspace, member: member)
    @openrouter_chat.update_columns(chosen_model: "deepseek/deepseek-v4-flash")
    @other_chat = Conversation.start_personal!(workspace: @workspace, member: member)
    @other_chat.update_columns(chosen_model: "deepseek/deepseek-v4-pro")

    @direct = add_ai_account!(@workspace, key: "sk-direct")
    @direct.update_columns(provider: "deepseek", models: { "main" => "deepseek-v4-pro", "fast" => "deepseek-v4-flash" })
    @openrouter = add_ai_account!(@workspace, key: "sk-or")
    @openrouter.update_columns(provider: "openrouter", models: { "main" => "deepseek/deepseek-v4-flash" })
    @azure = add_ai_account!(@workspace, key: "sk-azure")
    @azure.update_columns(provider: "azure", models: { "main" => "deepseek-v4-flash" })

    @override = @workspace.ai_model_overrides.create!(purpose: AiPurpose::SUMMARY, model: "deepseek-v4-flash", provider: "deepseek")
    @other_override = @workspace.ai_model_overrides.create!(purpose: AiPurpose::POSTMORTEM, model: "deepseek-v4-flash", provider: "azure")
  end

  test "chats, accounts and overrides on DeepSeek V4 Flash move to V4.1 Flash under each provider's own name, and move back" do
    migrate(:up)

    assert_equal [ "deepseek-flash", "deepseek/deepseek-v4.1-flash", "deepseek/deepseek-v4-pro" ], [ @direct_chat, @openrouter_chat, @other_chat ].map { |chat| chat.reload.chosen_model }
    assert_equal({ "main" => "deepseek-v4-pro", "fast" => "deepseek-flash" }, @direct.reload.models)
    assert_equal({ "main" => "deepseek/deepseek-v4.1-flash" }, @openrouter.reload.models)
    assert_equal({ "main" => "deepseek-v4-flash" }, @azure.reload.models, "Azure's model of the same name is its own")
    assert_equal [ "deepseek-flash", "deepseek-v4-flash" ], [ @override.reload.model, @other_override.reload.model ]

    migrate(:down)

    assert_equal [ "deepseek-v4-flash", "deepseek/deepseek-v4-flash" ], [ @direct_chat.reload.chosen_model, @openrouter_chat.reload.chosen_model ]
    assert_equal({ "main" => "deepseek-v4-pro", "fast" => "deepseek-v4-flash" }, @direct.reload.models)
    assert_equal "deepseek-v4-flash", @override.reload.model
  end

  private

  def migrate(direction) = ActiveRecord::Migration.suppress_messages { MoveDeepseekV4FlashChoicesToV41Flash.new.migrate(direction) }
end
