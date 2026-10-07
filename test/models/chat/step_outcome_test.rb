require "test_helper"

class Chat::StepOutcomeTest < ActiveSupport::TestCase
  TOKEN = "ghp_#{'a' * 36}".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @chat = @workspace.chats.create!(owner: conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    @asking = @chat.add_message(role: :assistant, content: "")
  end

  test "a call that answered shows how its answer starts, how long it is and the page it came from, out of its frame" do
    answer = "zone firefight.app active\nzone ember.dev active\n\nzone old.dev moved\nzone four.dev active\nzone five.dev active\n" \
             "Open this in Cloudflare, and give the person this link with what you found: https://dash.cloudflare.com/acc/firefight.app"
    call = call_with(FirefightAi::Evidence.frame("cloudflare_execute", answer) + "\n\nLoad the cloudflare skill before the next call.")

    outcome = Chat::StepOutcome.for_call(call, @chat)

    assert_equal Chat::StepOutcome::KIND_ANSWERED, outcome.kind
    assert_equal [ "zone firefight.app active", "zone ember.dev active", "zone old.dev moved", "zone four.dev active" ], outcome.lines
    assert_equal [ 5, answer.length ], [ outcome.total, outcome.size ]
    assert_equal({ provider: "Cloudflare", url: "https://dash.cloudflare.com/acc/firefight.app" }, outcome.to_h[:link])
    assert_nil outcome.said
  end

  test "JSON laid out over many lines is shown as one line of what it holds" do
    answer = JSON.pretty_generate("result" => [ { "id" => "ember-landing", "handlers" => [ "fetch" ] } ])

    outcome = Chat::StepOutcome.for_call(call_with(FirefightAi::Evidence.frame("cloudflare_execute", answer)), @chat)

    assert_equal [ '{"result":[{"id":"ember-landing","handlers":["fetch"]}]}' ], outcome.lines
    assert_equal answer.lines.size, outcome.total
  end

  test "a failed call shows the provider's own words, without how Firefight introduced them" do
    call = call_with(FirefightAi::Evidence.frame("vercel_list_projects", "vercel.list_projects failed: Vercel answered 500: Internal error\nretry later"))
    call.update!(failed: true)

    outcome = Chat::StepOutcome.for_call(call, @chat)

    assert_equal [ Chat::StepOutcome::KIND_FAILED, "Vercel answered 500: Internal error retry later" ], [ outcome.kind, outcome.said ]
    assert_empty outcome.lines
  end

  test "a not found reads as one, in the provider's words, and a refusal Firefight wrote is shown as it was said" do
    found_nothing = call_with(FirefightAi::Evidence.frame("cloudflare_execute", "Error: Cloudflare API error: 8000007: Project not found."))
    found_nothing.update!(failed: true, failure_kind: Chat::StepOutcome::FAILURE_NOT_FOUND)
    refused = call_with("Not allowed: Alice cannot use cloudflare.execute in this workspace.", id: "call_2")
    refused.update!(failed: true)

    assert_equal [ Chat::StepOutcome::KIND_NOT_FOUND, "Cloudflare API error: 8000007: Project not found." ],
                 Chat::StepOutcome.for_call(found_nothing, @chat).then { |outcome| [ outcome.kind, outcome.said ] }
    assert_equal "Not allowed: Alice cannot use cloudflare.execute in this workspace.", Chat::StepOutcome.for_call(refused, @chat).said
  end

  test "a secret in what came back is redacted, whether the call answered or failed" do
    answered = call_with(FirefightAi::Evidence.frame("github_fetch_file", "token = #{TOKEN}"))
    failed = call_with(FirefightAi::Evidence.frame("github_fetch_file", "Error: bad token #{TOKEN}"), id: "call_2")
    failed.update!(failed: true)

    shown = [ Chat::StepOutcome.for_call(answered, @chat), Chat::StepOutcome.for_call(failed, @chat) ].map(&:to_h).to_json

    assert_not_includes shown, TOKEN
    assert_includes shown, "[REDACTED:github_token]"
  end

  test "an answer too large to hand over is measured by what was kept whole, not by its preview" do
    whole = (1..300).map { |number| "row #{number}" }.join("\n")
    saved = @chat.saved_results.keep!(tool_name: "search_logs", text: whole)
    preview = FirefightAi::Evidence.preview(whole, handle: saved.handle, read_with: Chat::SavedResult::READ_WITH)

    outcome = Chat::StepOutcome.for_call(call_with(FirefightAi::Evidence.frame("search_logs", preview)), @chat)

    assert_equal [ [ "row 1", "row 2", "row 3", "row 4" ], 300, whole.length ], [ outcome.lines, outcome.total, outcome.size ]
  end

  test "a call with no answer yet has nothing to show" do
    call = RubyLLM::ActiveRecord::ToolCall.create!(message: @asking, tool_call_id: "call_9", name: "search_logs", arguments: {})

    assert_nil Chat::StepOutcome.for_call(call, @chat)
  end

  test "a run's step reads the same way, a provider's answered error included though the step ran" do
    investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    raised = investigation.steps.create!(position: 1, tool_name: "vercel_list_projects", status: Investigation::Step::STATUS_RUNNING)
    raised.fail!("NotFound: Vercel answered 404: Project not found", kind: Chat::StepOutcome::FAILURE_NOT_FOUND)
    answered_error = investigation.steps.create!(position: 2, tool_name: "cloudflare_execute", status: Investigation::Step::STATUS_RUNNING)
    answered_error.succeed!(compacted_result: "Error: Cloudflare API error: 10000: Authentication error", failure_kind: Chat::StepOutcome::FAILURE_ERROR)
    answered = investigation.steps.create!(position: 3, tool_name: "search_logs", status: Investigation::Step::STATUS_RUNNING)
    answered.succeed!(compacted_result: "one\ntwo", raw_result: "one\ntwo")
    running = investigation.steps.create!(position: 4, tool_name: "search_logs", status: Investigation::Step::STATUS_RUNNING)

    assert_equal [ Chat::StepOutcome::KIND_NOT_FOUND, "Vercel answered 404: Project not found" ], Chat::StepOutcome.for_step(raised).to_h.values_at(:kind, :said)
    assert_equal [ Chat::StepOutcome::KIND_FAILED, "Cloudflare API error: 10000: Authentication error" ],
                 Chat::StepOutcome.for_step(answered_error).to_h.values_at(:kind, :said)
    assert_equal [ Chat::StepOutcome::KIND_ANSWERED, [ "one", "two" ] ], Chat::StepOutcome.for_step(answered).to_h.values_at(:kind, :lines)
    assert_nil Chat::StepOutcome.for_step(running)
  end

  private

  def call_with(content, id: "call_1")
    result = @chat.add_message(role: :tool, content: content)
    RubyLLM::ActiveRecord::ToolCall.create!(message: @asking, tool_call_id: id, name: "cloudflare_execute", arguments: {}, result: result)
  end
end
