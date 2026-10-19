require "test_helper"

# Undo on a change Halon made without asking runs only the one call the registry declares to put it back, built from the
# call and what it answered, on the same connection, through the gateway. No model writes it, and it can never reach a
# tool that changes access, writes rows or stops something.
class Conversation::MadeUndoTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @chat = conversation.chat_record
    @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    @github.integration_environments.create!(credentials: { token: "x" }.to_json)
    @label = tool!(@github, "label_issue")
    @comment = tool!(@github, "comment_on_issue")
    @delete = tool!(@github, "delete_issue_comment")
    @sent = []
    sent = @sent
    executor = Object.new
    executor.define_singleton_method(:call) do |tool:, arguments:, **|
      sent << [ tool.name, arguments ]
      { "content" => [ { "type" => "text", "text" => "Done." } ] }
    end
    Integration.any_instance.stubs(:executor).returns(executor)
    WorkspaceAdapter.stubs(:for).returns(stub_everything("adapter", direct_conversation?: false))
    FirefightAi::UndoWriter.any_instance.expects(:write).never
  end

  def tool!(integration, name)
    integration.tools.create!(name: name, description: name, enabled: true, read_only: false, params_schema: { "type" => "object" })
  end

  test "a label's undo takes off exactly the labels it added, from the registry, ready at once" do
    inverse = Integrations::SafeChanges.inverse(@label, { "repo" => "acme/shop", "number" => 12, "add" => [ "bug" ] }, {})

    assert_equal [ @label, { "repo" => "acme/shop", "number" => 12, "remove" => [ "bug" ] } ], [ inverse.tool, inverse.arguments ]
  end

  test "a comment's undo deletes that exact comment by the id its answer named, and none without the id" do
    answer = { "content" => [], Integrations::Telemetry::STRUCTURED => { Integrations::Telemetry::FACTS => { "comment_id" => 41 } } }
    inverse = Integrations::SafeChanges.inverse(@comment, { "repo" => "acme/shop", "number" => 12, "body" => "Mitigated" }, answer)

    assert_equal [ @delete, { "repo" => "acme/shop", "comment_id" => 41 } ], [ inverse.tool, inverse.arguments ]
    assert_nil Integrations::SafeChanges.inverse(@comment, { "repo" => "acme/shop", "number" => 12, "body" => "Mitigated" }, {})
  end

  test "a safe tool with no declared undo, and any risky tool, offer none" do
    assert_nil Integrations::SafeChanges.inverse(tool!(@github, "rerun_workflow"), { "repo" => "acme/shop", "run_id" => 9 }, {})
    assert_nil Integrations::SafeChanges.inverse(tool!(@github, "merge_pull_request"), { "repo" => "acme/shop", "number" => 7 }, {})
  end

  test "Undo runs the declared call as the asker through the gateway, and Halon hears it was undone" do
    made = made!(@label, [ step(@label, "repo" => "acme/shop", "number" => 12, "remove" => [ "bug" ]) ])

    assert_nil Conversation::Mitigations.undo_now!(made, by: @alice)
    perform_enqueued_jobs(only: MitigationUndoRunJob)

    assert_equal Chat::Mitigation::STATUS_UNDONE, made.reload.status
    assert_equal [ [ "label_issue", { "repo" => "acme/shop", "number" => 12, "remove" => [ "bug" ] } ] ], @sent
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: @label.action_key, principal_id: @alice.id)
  end

  test "an undo that names a tool that may not be one, or another connection's, never runs" do
    secret = tool!(@github, "set_actions_secret")
    other = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "Other", slug: "other_github")
    other.integration_environments.create!(credentials: { token: "x" }.to_json)
    elsewhere = tool!(other, "label_issue")

    [ step(secret, "repo" => "acme/shop", "name" => "TOKEN"), step(elsewhere, "repo" => "acme/shop", "number" => 12) ].each do |bad|
      made = made!(@label, [ bad ])
      Conversation::Mitigations.undo_now!(made, by: @alice)
      perform_enqueued_jobs(only: MitigationUndoRunJob)

      assert_equal Chat::Mitigation::STATUS_UNDO_FAILED, made.reload.status
    end
    assert_empty @sent
  end

  private

  def step(tool, arguments) = { "description" => tool.name, "action_key" => tool.action_key, "arguments" => arguments, "declared" => true }

  def made!(tool, steps)
    Chat::Mitigation.create!(chat: @chat, workspace: @workspace, asker: @alice, tool_call_id: "call_#{SecureRandom.hex(3)}", tool_name: tool.model_facing_name,
                             action_key: tool.action_key, arguments: {}, intent: "Label issue 12", status: Chat::Mitigation::STATUS_MADE, started_at: Time.current,
                             told_at: Time.current, undo_state: Chat::Mitigation::UNDO_READY, undo_steps: steps, unasked_reason: Ability::Invocation::UNASKED_SAFE)
  end
end
