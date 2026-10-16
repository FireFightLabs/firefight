require "application_system_test_case"

# A chart Halon placed sits where it placed it wherever its answer is read on the dashboard: a run's card in the chat,
# the run itself, and the chat beside a workflow's canvas.
class InlineChartsElsewhereTest < ApplicationSystemTestCase
  STARTED = Time.utc(2026, 9, 25, 14, 0)

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "a run's card in the chat sets its charts in its answer, and one the answer placed nowhere follows it" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    conversation.ask!("why is checkout slow")
    reply = conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: FirefightTools::START_INVESTIGATION, arguments: { "symptom" => "Checkout is slow" })
    conversation.chat.add_message(role: :tool, content: "Started.", tool_call_id: "call_1")
    conversation.note!("It is running. Its answer will come back here.")
    conversation.reply_delivered!
    run = @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_CONVERSATION, triggered_by: @alice, max_turns: 10, max_spend_cents: 400,
      conversation: conversation, tool_call_id: "call_1", status: Investigation::STATUS_SUCCEEDED,
      started_at: 1.minute.ago, completed_at: Time.current, brief: { Investigation::Brief::KEY_SYMPTOM => "Checkout is slow" }
    )
    pool, cpu = drawn(run.chat_record, "Connections of orders-db", "CPU of checkout")
    run.conclude!(summary: "The orders database ran out of connections at 14:02.\n\n#{Chat::Chart::Marker.for(pool)}\n\nCheckout's writes time out since.")

    visit agent_chat_path(conversation)

    within("section[aria-label='Investigation']") do
      assert_text(/ran out of connections at 14:02\..*Connections of orders-db.*writes time out since\..*CPU of checkout/m)
      assert_no_text "{{chart"
    end
    assert_operator top(cpu.title), :>, top(pool.title)
    page.save_screenshot(Rails.root.join("tmp/screenshots/inline-charts-run-card.png"))
  end

  test "the run's answer sets its charts where it placed them" do
    incident = incidents(:active_critical_ws1)
    run = @workspace.investigations.create!(
      subject: incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: @alice, max_turns: 10, max_spend_cents: 400,
      status: Investigation::STATUS_SUCCEEDED, started_at: 1.minute.ago, completed_at: Time.current,
      brief: { Investigation::Brief::KEY_SYMPTOM => "Checkout is slow" }
    )
    pool, = drawn(run.chat_record, "Connections of orders-db")
    run.note_answered!(run.conclude!(summary: "The orders database ran out of connections at 14:02.\n\n#{Chat::Chart::Marker.for(pool)}\n\nCheckout's writes time out since."))

    visit incident_path(incident, Investigation::QUERY_PARAM => run.id)

    within("[role=dialog]") do
      assert_text(/ran out of connections at 14:02\..*Connections of orders-db.*writes time out since\./m)
      assert_no_text "{{chart"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/inline-charts-run-page.png"))
  end

  test "the chat beside a workflow's canvas sets Halon's charts in its answer" do
    workflow = Workflow.create!(workspace: @workspace, name: "Release check")
    workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, by: @alice,
                   payload: { "step" => { "id" => "wait", "name" => "wait_a_bit", "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 1 } } })
    conversation = Conversation::Asking.start_personal(workspace: @workspace, member: @alice, question: "How much memory does web use?", subject: workflow)
    chat = conversation.chat_record
    reply = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: "northflank_query_metrics", arguments: { "resource" => "web" })
    chat.add_message(role: :tool, content: "Memory of web", tool_call_id: "call_1")
    web, = drawn(chat, "Memory of web", tool_call_id: "call_1")
    conversation.note!("Web climbed at 14:40.\n\n#{Chat::Chart::Marker.for(web)}\n\nIt came back down by 15:00.")
    conversation.reply_delivered!

    visit workflow_path(workflow)
    click_button "Ask Halon"

    within("aside[aria-label='Halon']") do
      assert_text(/Web climbed at 14:40\..*Memory of web.*It came back down by 15:00\./m)
      assert_no_text "{{chart"
      assert_no_text "Halon showed more here"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/inline-charts-workflow-chat.png"))
  end

  private

  def drawn(chat, *titles, tool_call_id: "call_9")
    Chat::Chart.record!(chat, tool_call_id, titles.map do |title|
      { "title" => title, "unit" => "count", "from" => STARTED.iso8601, "to" => (STARTED + 59.minutes).iso8601,
        "series" => [ { "label" => "#{title.split.last}-1", "points" => (0..59).map { |minute| [ (STARTED + minute.minutes).iso8601, minute > 40 ? 90 : 20 ] } } ] }
    end)
  end

  def top(title)
    page.evaluate_script("document.querySelector(#{"figure[aria-label='#{title}']".to_json}).getBoundingClientRect().top + window.scrollY")
  end
end
