require "test_helper"

class AgentChatsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "the page is reachable in every workspace" do
    get agent_chats_url, headers: inertia_headers

    assert_response :success
    assert_equal [], inertia_props["conversations"]
  end

  test "an open chat arrives with what has been said in it" do
    conversation = start_chat
    conversation.ask!("What changed today?")

    get agent_chat_url(conversation), headers: inertia_headers

    assert_equal "What changed today?", inertia_props["messages"].sole["body"]
    assert_equal "What changed today?", inertia_props.dig("conversation", "title")
  end

  test "an open chat arrives with each time it made room, with when, and never the agent's note to itself" do
    conversation = start_chat
    conversation.ask!("What changed today?")
    compaction = conversation.chat.compactions.create!(stage: Chat::Compaction::STAGE_REBUILT, tokens_before: 150_000, note: "The pool config looks guilty")

    get agent_chat_url(conversation), headers: inertia_headers

    assert_equal [ { "key" => compaction.step_key, "title" => Chat::Compaction::SHOWN_AS, "at" => compaction.created_at.utc.iso8601(3) } ],
                 inertia_props[AgentChatsController::PROP_COMPACTIONS]
    assert_no_match "pool config", response.body
  end

  # Seen in a real chat. The page guessed from the last message's role, and the empty reply saved before the
  # model answers made it hide the agent's work until the answer landed.
  test "the page is told an answer is owed until the turn delivers it" do
    conversation = start_chat
    conversation.ask!("What changed today?")

    get agent_chat_url(conversation), headers: inertia_headers
    assert inertia_props.dig("conversation", "busy")

    conversation.reply_delivered!
    get agent_chat_url(conversation), headers: inertia_headers
    assert_not inertia_props.dig("conversation", "busy")
  end

  test "the model's own scaffolding is not read back to the person" do
    conversation = start_chat
    conversation.ask!("What changed today?")
    conversation.chat.messages.create!(role: "system", content: "You are Firefight, answering an engineer")
    conversation.chat.messages.create!(role: "tool", content: '{"incidents":[{"identifier":"INC-1"}]}')

    get agent_chat_url(conversation), headers: inertia_headers

    assert_equal [ "What changed today?" ], inertia_props["messages"].map { |message| message["body"] }
  end

  test "a step whose tool refused is read back as failed, not completed" do
    conversation = start_chat
    conversation.ask!("declare it")
    reply = conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: Mcp::Tools::DECLARE_INCIDENT, arguments: { "answers" => { "name" => "x" } })
    conversation.chat.add_message(role: :tool, content: "Not found in this workspace.", tool_call_id: "call_1")
    conversation.chat.mark_failed!("call_1")

    get agent_chat_url(conversation), headers: inertia_headers

    step = inertia_props["messages"].flat_map { |message| message["tools"] }.sole
    assert_equal Conversation::LiveDelivery::STATUS_FAILED, step["status"]
    assert_equal "x", step["headline"]
  end

  test "a category of integrations shown in a chat arrives as a card, with the rows it draws" do
    conversation = start_chat
    conversation.ask!("what can we connect for logs")
    reply = conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: Mcp::Tools::LIST_INTEGRATIONS, arguments: { "category" => "Observability" })
    conversation.chat.add_message(role: :tool, content: "{}", tool_call_id: "call_1")

    get agent_chat_url(conversation), headers: inertia_headers

    step = inertia_props["messages"].flat_map { |message| message["tools"] }.sole
    assert_equal({ "kind" => Chat::Tools::CARD_INTEGRATIONS, "category" => "observability" }, step["card"])
    telemetry = inertia_props["integrationCards"].find { |card| card["category"] == "observability" }
    assert_includes telemetry["rows"].map { |row| row.dig("provider", "key") }, "datadog"
  end

  test "the agent's nudge to itself is not read back as something the person said" do
    conversation = start_chat
    conversation.ask!("What changed today?")
    conversation.chat.nudge!(FirefightAi::AgentLoop::LAST_TURN)

    get agent_chat_url(conversation), headers: inertia_headers

    assert_equal [ "What changed today?" ], inertia_props["messages"].map { |message| message["body"] }
  end

  test "a workspace whose plan does not include AI is sent back with the reason" do
    deny_entitlements!

    get agent_chats_url

    assert_redirected_to dashboard_path
    assert_equal Investigation.unavailable_reason(@workspace), flash[:alert]
  end

  test "the first question starts the chat and is answered in the background" do
    assert_difference -> { @workspace.conversations.personal.count }, 1 do
      post agent_chats_url, params: { question: "what changed today" }
    end

    conversation = @workspace.conversations.personal.find_by!(started_by: @member)
    assert_redirected_to agent_chat_path(conversation)
    assert_equal "what changed today", conversation.title
    assert_enqueued_with(job: ConversationReplyJob, args: [ conversation.id, @member.id ])
  end

  test "a new chat with nothing asked is never created" do
    assert_no_difference -> { @workspace.conversations.personal.count } do
      post agent_chats_url, params: { question: "  " }
    end

    assert_redirected_to agent_chats_url
    assert_equal "Say something first.", flash[:alert]
  end

  test "a question is answered in the background" do
    conversation = start_chat

    assert_enqueued_with(job: ConversationReplyJob, args: [ conversation.id, @member.id ]) do
      post agent_chat_ask_url(conversation), params: { question: "what changed today" }
    end

    assert_redirected_to agent_chat_path(conversation)
    assert_equal "what changed today",
                 conversation.chat.messages.where(role: Chat::Message::ROLE_USER).sole.content
  end

  test "an empty question is not sent to the model" do
    conversation = start_chat

    assert_no_enqueued_jobs(only: ConversationReplyJob) do
      post agent_chat_ask_url(conversation), params: { question: "   " }
    end

    assert_equal "Say something first.", flash[:alert]
  end

  test "someone else's chat is not readable" do
    theirs = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:bob_workspace_one))

    get agent_chat_url(theirs), headers: inertia_headers

    assert_response :not_found
  end

  test "a chat in another workspace is not readable" do
    elsewhere = Conversation.start_personal!(
      workspace: workspaces(:slack_workspace_two), member: workspace_memberships(:alice_workspace_two)
    )

    get agent_chat_url(elsewhere), headers: inertia_headers

    assert_response :not_found
  end

  test "a chat can be renamed" do
    conversation = start_chat
    conversation.ask!("what changed today")

    patch agent_chat_url(conversation), params: { title: "Checkout latency" }

    assert_equal "Checkout latency", conversation.reload.title
    assert_equal "Chat renamed.", flash[:notice]
  end

  test "a chat cannot be renamed to nothing" do
    conversation = start_chat
    conversation.ask!("what changed today")

    patch agent_chat_url(conversation), params: { title: "   " }

    assert_equal "what changed today", conversation.reload.title
    assert_equal "A chat needs a name.", flash[:alert]
  end

  test "pinning puts a chat at the top of the list" do
    older = start_chat
    older.ask!("first question")
    newer = Conversation.start_personal!(workspace: @workspace, member: @member)
    newer.ask!("second question")

    patch agent_chat_url(older), params: { pinned: true }

    assert older.reload.pinned?
    assert_equal [ older.id, newer.id ], @workspace.conversations.personal.in_reading_order.map(&:id)
  end

  test "renaming, pinning or archiving a chat does not move the others" do
    older = start_chat
    older.ask!("first question")
    newer = Conversation.start_personal!(workspace: @workspace, member: @member)
    newer.ask!("second question")
    older.update_columns(updated_at: 1.hour.ago)

    patch agent_chat_url(older), params: { title: "Renamed" }
    patch agent_chat_url(older), params: { archived: false }

    assert_equal [ newer.id, older.id ], @workspace.conversations.personal.in_reading_order.map(&:id)
  end

  test "archiving from the list keeps the person where they were" do
    conversation = start_chat

    patch agent_chat_url(conversation), params: { archived: true }, headers: { "Referer" => agent_chats_url }

    assert conversation.reload.archived?
    assert_redirected_to agent_chats_url
    assert_equal "Chat archived.", flash[:notice]
  end

  test "an archived chat is still listed, so the page can offer it under its own filter" do
    conversation = start_chat
    conversation.archive!(true)

    get agent_chats_url, headers: inertia_headers

    listed = inertia_props["conversations"].map { |chat| [ chat["id"], chat["archived"] ] }
    assert_includes listed, [ conversation.id, true ]
  end

  test "deleting a chat takes its messages with it" do
    conversation = start_chat
    conversation.ask!("what changed today")
    chat_id = conversation.chat.id

    assert_difference -> { Chat.where(id: chat_id).count }, -1 do
      delete agent_chat_url(conversation)
    end

    assert_nil Conversation.find_by(id: conversation.id)
    assert_redirected_to agent_chats_path
    assert_equal "Chat deleted.", flash[:notice]
  end

  test "deleting a chat whose code fix paused at its spending limit keeps the pause and lets the chat go" do
    conversation = start_chat
    request = CodeAgent::Request.new(principal: @member, source: AbilityGateway::SOURCE_CONVERSATION, place: conversation, tool_call_id: "call_1")
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/api", request: request)
    pause = CodeAgentSession::Pause.create!(
      session: session, workspace: @workspace, conversation: conversation, arguments: { "repo" => "acme/api" }, repository: "acme/api",
      base: "main", copy_ref: "c" * 40, budget_micros: 2_000_000, resumable_until: 15.minutes.from_now
    )

    delete agent_chat_url(conversation)

    assert_nil Conversation.find_by(id: conversation.id)
    assert_nil pause.reload.conversation_id
  end

  test "deleting another chat from the list keeps the open one open" do
    open_chat = start_chat
    other = Conversation.start_personal!(workspace: @workspace, member: @member)

    delete agent_chat_url(other), headers: { "Referer" => agent_chat_url(open_chat) }

    assert_redirected_to agent_chat_url(open_chat)
    assert_equal "Chat deleted.", flash[:notice]
  end

  test "deleting the open chat goes back to a new one" do
    conversation = start_chat

    delete agent_chat_url(conversation), headers: { "Referer" => agent_chat_url(conversation) }

    assert_redirected_to agent_chats_path
  end

  test "a member tidies their own chats without any grant on investigations" do
    sign_in(users(:bob), @workspace)
    bob = workspace_memberships(:bob_workspace_one)
    conversation = Conversation.start_personal!(workspace: @workspace, member: bob)

    patch agent_chat_url(conversation), params: { title: "Mine" }
    assert_equal "Mine", conversation.reload.title

    delete agent_chat_url(conversation)
    assert_nil Conversation.find_by(id: conversation.id)
  end

  test "a member asks the agent without any grant, in a new chat and in one already open" do
    sign_in(users(:bob), @workspace)
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:bob_workspace_one))

    assert_enqueued_jobs(2, only: ConversationReplyJob) do
      post agent_chats_url, params: { question: "what changed today" }
      post agent_chat_ask_url(conversation), params: { question: "and yesterday" }
    end
    assert_nil flash[:alert]
  end

  test "a member an admin took asking away from is refused with the sentence every refused page says" do
    sign_in(users(:bob), @workspace)
    bob = workspace_memberships(:bob_workspace_one)
    conversation = Conversation.start_personal!(workspace: @workspace, member: bob)
    take_halon_from(@workspace, bob)

    assert_no_enqueued_jobs(only: ConversationReplyJob) do
      post agent_chats_url, params: { question: "what changed today" }
      post agent_chat_ask_url(conversation), params: { question: "what changed today" }
    end
    assert_equal WebAuthorization.denied_message(AbilityGateway::Denied.new(Ability::Action::INVESTIGATIONS_CREATE)), flash[:alert]
  end

  test "someone else's chat cannot be renamed or deleted" do
    theirs = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:bob_workspace_one))

    patch agent_chat_url(theirs), params: { title: "mine now" }
    assert_response :not_found

    delete agent_chat_url(theirs)
    assert_response :not_found
    assert Conversation.exists?(theirs.id)
  end

  test "the list says what was last said in each chat" do
    conversation = start_chat
    conversation.ask!("what changed today")
    conversation.note!("Two deploys went out.")

    get agent_chats_url, headers: inertia_headers

    listed = inertia_props["conversations"].find { |chat| chat["id"] == conversation.id }
    assert_equal "Two deploys went out.", listed["preview"]
  end

  test "the list loads a page at a time, and says when there is another" do
    AgentChatsController.any_instance.stubs(:chats_per_page).returns(2)
    3.times { |index| Conversation.start_personal!(workspace: @workspace, member: @member).ask!("question #{index}") }

    get agent_chats_url, headers: inertia_headers
    assert_equal 2, inertia_props["conversations"].size
    assert_equal 2, response.parsed_body.dig("scrollProps", "conversations", "nextPage")

    get agent_chats_url(page: 2), headers: inertia_headers.merge(
      "X-Inertia-Partial-Component" => "agent/index", "X-Inertia-Partial-Data" => "conversations"
    )
    assert_equal 1, inertia_props["conversations"].size
    assert_nil response.parsed_body.dig("scrollProps", "conversations", "nextPage")
  end

  test "archived chats come last, and the page is told how many there are" do
    archived = start_chat
    archived.ask!("old question")
    archived.archive!(true)
    current = Conversation.start_personal!(workspace: @workspace, member: @member)
    current.ask!("new question")
    archived.update_columns(updated_at: 1.minute.from_now)

    get agent_chats_url, headers: inertia_headers

    assert_equal [ current.id, archived.id ], inertia_props["conversations"].map { |chat| chat["id"] }
    assert_equal 1, inertia_props["archivedCount"]
  end

  test "search finds any of the person's chats, not only the loaded ones, and nobody else's" do
    AgentChatsController.any_instance.stubs(:chats_per_page).returns(1)
    older = start_chat
    older.ask!("why did checkout fail")
    Conversation.start_personal!(workspace: @workspace, member: @member).ask!("latest question")
    Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:bob_workspace_one))
      .ask!("checkout is down for bob")

    get agent_chats_search_url(q: "CHECKOUT"), as: :json

    assert_equal [ older.id ], response.parsed_body.map { |chat| chat["id"] }
  end

  test "@ searches every active incident by name" do
    incident = incidents(:active_critical_ws1)

    get agent_chats_incidents_url(q: incident.name.split.first), as: :json

    assert_includes response.parsed_body.map { |found| found["id"] }, incident.id
  end

  test "a paused change is shown as a question, and answering it carries the turn on as the person" do
    conversation = start_chat
    conversation.ask!("delete the test permission set")
    message = conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: "delete_permission_set", arguments: { "slug" => "test" })
    conversation.chat.request_decisions!([ "call_1" ])

    get agent_chat_url(conversation), headers: inertia_headers
    assert_equal [ "call_1" ], inertia_props["confirmations"].map { |confirmation| confirmation["toolCallId"] }

    assert_enqueued_with(job: ConversationReplyJob, args: [ conversation.id, @member.id ]) do
      post agent_chat_confirm_url(conversation), params: { decisions: [ { tool_call_id: "call_1", approved: "true" } ] }
    end
    assert_empty conversation.chat.awaiting_decision
  end

  test "allowing a call for the rest of the chat keeps its tool from asking again" do
    conversation = start_chat
    conversation.ask!("delete the test permission sets")
    message = conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    %w[call_1 call_2].each { |id| message.ruby_llm_tool_calls.create!(tool_call_id: id, name: "delete_permission_set", arguments: { "slug" => id }) }
    conversation.chat.request_decisions!(%w[call_1 call_2])

    get agent_chat_url(conversation), headers: inertia_headers
    assert_equal [ "delete_permission_set" ] * 2, inertia_props["confirmations"].map { |confirmation| confirmation["tool"] }

    assert_enqueued_with(job: ConversationReplyJob) do
      post agent_chat_confirm_url(conversation), params: { decisions: [ { tool_call_id: "call_1", approved: "true", for_chat: "true" } ] }
    end
    assert_empty conversation.chat.awaiting_decision
    assert conversation.chat.reload.allows_tool?("delete_permission_set")
  end

  test "a step says what it was about without the page choosing" do
    conversation = start_chat
    conversation.ask!("what changed today")
    reply = conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(
      tool_call_id: "call_1", name: "search_incidents", arguments: { "limit" => 5, "query" => "checkout" }
    )

    get agent_chat_url(conversation), headers: inertia_headers

    step = inertia_props["messages"].flat_map { |message| message["tools"] }.sole
    assert_equal "Search incidents", step["title"]
    assert_equal "checkout", step["headline"]
  end

  test "an open chat carries the runs it started, and opens one of them over itself" do
    chat = Conversation.start_personal!(workspace: @workspace, member: @member)
    run = @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_CONVERSATION, triggered_by: @member, max_turns: 10, max_spend_cents: 400,
      conversation: chat, tool_call_id: "call_1", brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )
    run.steps.create!(position: 1, tool_name: "commit_lookup", label: "Commit lookup abc123", status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current)
    run.steps.create!(position: nil, tool_name: "search_logs", status: Investigation::Step::STATUS_RUNNING, started_at: Time.current)

    get agent_chat_url(chat, Investigation::QUERY_PARAM => run.id), headers: inertia_headers

    card = inertia_props[AgentChatsController::PROP_INVESTIGATIONS].sole
    assert_equal [ "call_1", "checkout is slow" ], [ card["toolCallId"], card["question"] ]
    assert_equal [ "Commit lookup abc123" ], card["steps"].map { |step| step["label"] }
    assert_equal run.id, inertia_props.dig(AgentChatsController::PROP_OPEN_INVESTIGATION, "id")
  end

  test "a file on a run this chat started opens for whoever may read the chat, without investigations read" do
    bob = workspace_memberships(:bob_workspace_one)
    chat = Conversation.start_personal!(workspace: @workspace, member: bob)
    run = chat_run(chat)
    file = Chat::Attachment.take!(workspace: @workspace, uploaded_by: bob, filename: "a.log", bytes: "a")
    run.add_note!("", by: bob, files: [ file ])
    sign_in(users(:bob), @workspace)
    WorkspaceMembership.any_instance.stubs(:implicitly_permits?).returns(true)
    WorkspaceMembership.any_instance.stubs(:implicitly_permits?).with(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_READ, nil).returns(false)

    get agent_chat_url(chat, Investigation::QUERY_PARAM => run.id), headers: inertia_headers
    url = inertia_props.dig(AgentChatsController::PROP_OPEN_INVESTIGATION, "notes").flat_map { |note| note["files"] }.sole["url"]
    assert_equal agent_chat_investigation_file_path(chat, run, file), url

    get url
    assert_response :success
    assert_equal "a", response.body
  end

  test "a file on a run opens under a chat only for the person whose chat started it" do
    theirs = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:bob_workspace_one))
    run = chat_run(theirs)
    file = Chat::Attachment.take!(workspace: @workspace, uploaded_by: @member, filename: "a.log", bytes: "a")
    run.add_note!("", by: @member, files: [ file ])
    mine = start_chat

    get agent_chat_investigation_file_url(theirs, run, file)
    assert_response :not_found

    get agent_chat_investigation_file_url(mine, run, file)
    assert_response :not_found
  end

  test "stopping an answer under way asks the worker to stop, and one with nothing running is refused" do
    conversation = start_chat
    conversation.ask!("anything in metrics?")

    post agent_chat_stop_url(conversation)

    assert conversation.chat.reload.stop_requested?

    conversation.reply_delivered!
    conversation.chat.clear_stop!
    post agent_chat_stop_url(conversation)

    assert_equal Conversation::NOTHING_TO_STOP, flash[:alert]
    assert_not conversation.chat.reload.stop_requested?
  end

  test "an open chat arrives with each call an approval rule held, what Halon read, when it expires and what the viewer may do" do
    conversation = start_chat
    held = held_call_in(conversation, status: Chat::HeldCall::STATUS_READY)

    get agent_chat_url(conversation), headers: inertia_headers

    shown = inertia_props[AgentChatsController::PROP_HELD_CALLS].sole
    assert_equal [ held.id, "Bob Jones approved: Resolve incident. Run it now?", "This looks done already.", "INC-1 is already resolved." ],
                 shown.values_at("id", "headline", "warning", "state")
    assert_equal [ [ "run", "dismiss" ], nil ], shown.values_at("offers", "runBlockedReason")
    assert shown["expiresAt"]
  end

  test "Run hands the approved call to the chat's next turn once, and Dismiss on a call that already ran is refused with why" do
    conversation = start_chat
    held = held_call_in(conversation, status: Chat::HeldCall::STATUS_READY)
    ConversationChannel.stubs(:broadcast_to)

    assert_enqueued_with(job: ConversationReplyJob, args: [ conversation.id, @member.id, held.id ]) do
      post agent_chat_held_call_run_url(conversation, held)
    end
    assert_equal "Running it now.", flash[:notice]

    post agent_chat_held_call_dismiss_url(conversation, held)
    assert_equal "This is no longer waiting to be run.", flash[:alert]
    assert_equal Chat::HeldCall::STATUS_RUNNING, held.reload.status
  end

  private

  def held_call_in(conversation, status:)
    approval = @workspace.ability_approvals.create!(
      principal: @member, principal_label: "user:Alice Smith", action_key: "incidents.update", request_digest: "d", required_role: "admin",
      status: Ability::Approval::STATUS_APPROVED, approver: workspace_memberships(:bob_workspace_one), held_for_run: true,
      run_expires_at: 52.minutes.from_now, resolved_at: Time.current
    )
    Chat::HeldCall.create!(chat: conversation.chat_record, approval: approval, tool_name: "resolve_incident", status: status,
                           checked_state: "INC-1 is already resolved.", state_change: Chat::CurrentState::DONE_ALREADY, state_checked_at: Time.current)
  end

  def chat_run(chat)
    @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_CONVERSATION, triggered_by: @member, max_turns: 10, max_spend_cents: 400,
      conversation: chat, tool_call_id: "call_1", status: Investigation::STATUS_RUNNING,
      brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )
  end

  def start_chat
    Conversation.start_personal!(workspace: @workspace, member: @member)
  end
end
