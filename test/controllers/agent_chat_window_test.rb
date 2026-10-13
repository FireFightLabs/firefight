require "test_helper"

class AgentChatWindowTest < ActionDispatch::IntegrationTest
  START = Time.utc(2026, 10, 1, 9, 0)

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.ask!("Why is checkout slow?")
    @chat = @conversation.chat_record
    @messages = [ @chat.messages.sole ]
    @messages.first.update_columns(created_at: START)
    (1...60).each { |index| @messages << said(index.even? ? Chat::Message::ROLE_USER : Chat::Message::ROLE_ASSISTANT, "Message #{index}", at: START + index.minutes) }
    @conversation.reply_delivered!
  end

  test "a chat shows at once with what its composer needs, and its conversation follows as one group" do
    get agent_chat_url(@conversation), headers: inertia_headers

    page = JSON.parse(response.body)
    assert_equal({ AgentChatsController::THREAD_GROUP => AgentChatsController::THREAD_PROPS }, page["deferredProps"])
    assert_equal @conversation.id, inertia_props.dig("conversation", "id")
    assert inertia_props.key?("attachmentRules")
    assert_empty AgentChatsController::THREAD_PROPS & inertia_props.keys
  end

  test "a page already showing the chat, coming back to it after a change, gets the stretch it shows at once rather than a skeleton" do
    from = @messages[4]

    get agent_chat_url(@conversation), headers: inertia_headers.merge(AgentChatsController::LOADED_FROM_HEADER => from.id)

    assert_nil JSON.parse(response.body)["deferredProps"]
    assert_equal @messages[4..].reverse.map(&:id), inertia_props["messages"].pluck("id")
    assert_equal @conversation.id, inertia_props["threadFor"]
    assert_equal from.id, scroll_props["nextPage"]
  end

  test "the conversation arrives with the newest page of messages and the way to the page before it" do
    get agent_chat_url(@conversation), headers: thread_headers

    newest = @messages.last(Chat::Window::PAGE)
    assert_equal newest.reverse.map(&:id), inertia_props["messages"].pluck("id"), "newest first, as Inertia pages in reverse"
    assert_equal @conversation.id, inertia_props["threadFor"]
    assert_equal({ "pageName" => AgentChatsController::MESSAGES_BEFORE_PARAM, "currentPage" => newest.first.id, "previousPage" => nil,
                   "nextPage" => newest.first.id, "reset" => false }, scroll_props)
  end

  test "scrolling up reads the page before the oldest shown until the start, and the pages meet without dropping or repeating a message" do
    tied = START + 30.minutes + 15.seconds
    @messages.insert(31, *Array.new(3) { |index| said(Chat::Message::ROLE_ASSISTANT, "Said at the same moment #{index}", at: tied) })
    expected = @chat.readable_messages.reorder(created_at: :desc, id: :desc).pluck(:id)

    get agent_chat_url(@conversation), headers: thread_headers
    shown = inertia_props["messages"].pluck("id")
    pages = 1
    while (before = scroll_props["nextPage"])
      get agent_chat_url(@conversation, AgentChatsController::MESSAGES_BEFORE_PARAM => before), headers: older_page_headers
      assert_equal [ "messages" ], JSON.parse(response.body)["mergeProps"]
      assert_includes JSON.parse(response.body)["matchPropsOn"], "messages.id"
      shown += inertia_props["messages"].pluck("id")
      pages += 1
    end

    assert_equal expected, shown
    assert_equal 2, pages
  end

  test "a reload names the oldest message the page shows and keeps that stretch, and one that is not in this chat reads the newest page" do
    from = @messages[4]

    get agent_chat_url(@conversation), headers: thread_headers.merge(AgentChatsController::LOADED_FROM_HEADER => from.id)
    assert_equal @messages[4..].reverse.map(&:id), inertia_props["messages"].pluck("id")
    assert_equal [ from.id, from.id ], scroll_props.values_at("currentPage", "nextPage")

    get agent_chat_url(@conversation), headers: thread_headers.merge(AgentChatsController::LOADED_FROM_HEADER => @messages.first.id)
    assert_nil scroll_props["nextPage"]

    elsewhere = Conversation.start_personal!(workspace: @workspace, member: @member)
    elsewhere.ask!("Another chat")
    get agent_chat_url(@conversation), headers: thread_headers.merge(AgentChatsController::LOADED_FROM_HEADER => elsewhere.chat.messages.sole.id)
    assert_equal @messages.last(Chat::Window::PAGE).reverse.map(&:id), inertia_props["messages"].pluck("id")

    get agent_chat_url(@conversation, AgentChatsController::MESSAGES_BEFORE_PARAM => elsewhere.chat.messages.sole.id), headers: older_page_headers
    assert_empty inertia_props["messages"]
  end

  test "everything placed among the messages is read for the same stretch, and the rest of it arrives with the older page" do
    old_at = @messages[3].created_at + 30.seconds
    new_at = @messages[40].created_at + 30.seconds
    old_step = step_on(@messages[3], "call_old")
    new_step = step_on(@messages[40], "call_new")
    placed = { old: placed_rows(old_at, old_step), new: placed_rows(new_at, new_step) }
    late_news = held_call(created_at: old_at, resolved_at: new_at)

    get agent_chat_url(@conversation), headers: thread_headers
    AgentChatsController::WINDOWED_PROPS.each do |prop|
      assert_equal ids_of(placed[:new], prop).sort, (shown_ids(prop) - [ late_news.id ]).sort, "#{prop} reads only what sits beside the newest page"
    end
    assert_includes shown_ids(AgentChatsController::PROP_HELD_CALLS), late_news.id, "a held call sits where it last had news"

    get agent_chat_url(@conversation, AgentChatsController::MESSAGES_BEFORE_PARAM => @messages[10].id), headers: older_page_headers
    AgentChatsController::WINDOWED_PROPS.each do |prop|
      assert_equal (ids_of(placed[:old], prop) + ids_of(placed[:new], prop)).sort, (shown_ids(prop) - [ late_news.id ]).sort, "#{prop} reads the whole stretch shown"
    end
  end

  test "what is live arrives whatever its age: a confirmation waiting, a message waiting, a watch still going and a fix waiting to continue" do
    old_at = @messages[3].created_at + 30.seconds
    step_on(@messages[3], "call_waiting").update!(approval: Chat::APPROVAL_REQUESTED)
    @chat.queue_message!("And the worker?", sender: @member)
    going = watch(at: old_at)
    ended = watch(at: old_at, status: Chat::Watch::STATUS_SUCCEEDED)
    waiting_fix = code_pause("call_waiting_fix")
    decided_fix = code_pause("call_decided_fix", status: CodeAgentSession::Pause::STATUS_CONTINUING)
    [ waiting_fix, decided_fix ].each { |pause| pause.update_columns(created_at: old_at) }

    get agent_chat_url(@conversation), headers: thread_headers

    assert_equal [ "call_waiting" ], inertia_props["confirmations"].pluck("toolCallId")
    assert_equal [ "And the worker?" ], inertia_props["waitingMessages"].pluck("body")
    assert_equal [ going.id ], shown_ids(AgentChatsController::PROP_WATCHES)
    assert_not_includes shown_ids(AgentChatsController::PROP_WATCHES), ended.id
    assert_equal [ waiting_fix.id ], shown_ids(AgentChatsController::PROP_CODE_PAUSES)
  end

  test "a chat nobody has asked anything in yet has an empty conversation and nothing older" do
    empty = Conversation.start_personal!(workspace: @workspace, member: @member)

    get agent_chat_url(empty), headers: thread_headers

    assert_empty inertia_props["messages"]
    assert_equal [ nil, nil ], scroll_props.values_at("currentPage", "nextPage")
  end

  private

  def thread_headers = inertia_partial_headers("agent/index", AgentChatsController::THREAD_PROPS)

  # What the page asks for when the person scrolls up. Paging in reverse, Inertia adds the older page after what it holds.
  def older_page_headers
    inertia_partial_headers("agent/index", [ AgentChatsController::PROP_MESSAGES, *AgentChatsController::WINDOWED_PROPS ])
      .merge("X-Inertia-Infinite-Scroll-Merge-Intent" => "append")
  end

  def scroll_props = JSON.parse(response.body).dig("scrollProps", "messages")

  # A quiet line among the steps is known by its step key, everything else by its id.
  def shown_ids(prop) = inertia_props.fetch(prop).map { |shown| shown["id"] || shown["key"] }

  def ids_of(rows, prop) = Array(rows[prop]).map { |row| row.respond_to?(:step_key) ? row.step_key : row.id }

  def said(role, content, at:)
    message = @chat.messages.create!(role: role, content: content)
    message.update_columns(created_at: at)
    message
  end

  def step_on(message, key)
    message.ruby_llm_tool_calls.create!(tool_call_id: key, name: Mcp::Tools::SEARCH_INCIDENTS, arguments: { "query" => "checkout" })
  end

  # One of each thing the chat places by time or under a step, made at a time or under a step.
  def placed_rows(at, step)
    key = step.tool_call_id
    rows = {
      AgentChatsController::PROP_COMPACTIONS => @chat.compactions.create!(stage: Chat::Compaction::STAGE_REBUILT, tokens_before: 150_000),
      AgentChatsController::PROP_MODEL_SWITCHES => @chat.model_switches.create!(failed_model: "claude-opus-5-5", backup_model: "claude-haiku-5-5",
                                                                                 cause: Chat::ModelSwitch::CAUSES.first, reason: "OverloadedError"),
      AgentChatsController::PROP_HELD_CALLS => held_call(created_at: at, resolved_at: at),
      AgentChatsController::PROP_PACK_REFUSALS => Chat::PackRefusal.create!(chat: @chat, pack_request: pack_request(key), tool_call_id: key),
      AgentChatsController::PROP_SECRET_ENTRIES => @chat.secret_entries.create!(kind: Chat::SecretEntry::KIND_ENTER, status: Chat::SecretEntry::STATUS_PENDING,
                                                                                  tool: integration_tool, requester: @member, title: "DEPLOY_HOOK",
                                                                                  target: { "repo" => "acme/web", "name" => "DEPLOY_HOOK" }, expires_at: 1.hour.from_now),
      AgentChatsController::PROP_WATCHES => watch(at: at, status: Chat::Watch::STATUS_SUCCEEDED),
      AgentChatsController::PROP_PULL_REQUEST_NOTICES => pull_request_notice,
      AgentChatsController::PROP_CODE_PAUSES => code_pause(key, status: CodeAgentSession::Pause::STATUS_STOPPED),
      AgentChatsController::PROP_MEMORY_QUESTIONS => Chat::MemoryPost.create!(workspace: @workspace, conversation: @conversation, kind: Chat::MemoryPost::KIND_DISPUTED,
                                                                              memory_ids: [], evidence: "The deploy log says otherwise."),
      AgentChatsController::PROP_PLANS => Chat::Plan.make!(chat: @chat, made_by: @member, goal: "Release main to production",
                                                           steps: [ { "kind" => "read", "description" => "Read the latest commit on main", "place" => "GitHub" },
                                                                   { "kind" => "check", "description" => "Check checkout against normal", "place" => "checkout" } ]),
      AgentChatsController::PROP_DATA_REPAIRS => data_repair(key),
      AgentChatsController::PROP_MITIGATIONS => mitigation(key),
      AgentChatsController::PROP_OWNER_ASKS => Chat::OwnerAsk.create!(chat: @chat, workspace: @workspace, tool_call_id: key, tool_name: "northflank_restart_service",
                                                                     owner_name: "Bob Jones", owner_role: Integrations::Owner::ROLES.first, what: "web",
                                                                     status: Chat::OwnerAsk::STATUS_ASKED, asked_at: at),
      AgentChatsController::PROP_HANDBOOK_PROPOSALS => Chat::HandbookProposal.propose!(@conversation, title: "Deploys at #{at.to_i}", text: "Web deploys from main.",
                                                                                         evidence: "The deploy log."),
      AgentChatsController::PROP_INVESTIGATIONS => @workspace.investigations.create!(
        trigger_source: Investigation::TRIGGER_CONVERSATION, triggered_by: @member, max_turns: 10, max_spend_cents: 400, conversation: @conversation,
        tool_call_id: key, brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
      ),
      AgentChatsController::PROP_CHARTS => Chat::Chart.record!(@chat, key, [ chart ]) && @chat.charts.where(tool_call_id: key).to_a,
      AgentChatsController::PROP_SCREENSHOTS => Chat::Screenshot.record!(@chat, [ { "name" => "desktop", "final_url" => "https://shop.example.com", "title" => "Shop",
                                                                                 "screenshot" => Base64.strict_encode64("\xFF\xD8\xFFjpeg".b) } ], tool_call_id: key),
      AgentChatsController::PROP_HELPERS => Chat::Helper.start!(chat: @chat, tool_call_id: key, since: at,
                                                                checks: [ Chat::Helpers::Check.new(title: "Logs of web", brief: "Read web's errors", deep: false) ]) &&
                                                @chat.helpers.where(tool_call_id: key).to_a,
      AgentChatsController::PROP_THEORIES => Chat::Theory.create!(chat: @chat, workspace: @workspace, title: "Pool at #{key}", status: Chat::Theory::STATUS_OPEN,
                                                                  tool_call_id: key, position: @chat.theories.count, status_changed_at: at)
    }
    watch_update = rows[AgentChatsController::PROP_WATCHES].updates.create!(kind: Chat::Watch::Update::KINDS_ON_THEIR_OWN.first, text: "It passed.")
    rows[AgentChatsController::PROP_WATCH_UPDATES] = watch_update
    rows.except(AgentChatsController::PROP_HELD_CALLS, AgentChatsController::PROP_PLANS, AgentChatsController::PROP_DATA_REPAIRS, AgentChatsController::PROP_MITIGATIONS,
                AgentChatsController::PROP_OWNER_ASKS).each_value { |row| Array(row).each { |each| each.update_columns(created_at: at) } }
    rows[AgentChatsController::PROP_PLANS].update_columns(moved_at: at, created_at: at)
    rows[AgentChatsController::PROP_DATA_REPAIRS].update_columns(checked_at: at)
    rows[AgentChatsController::PROP_MITIGATIONS].update_columns(started_at: at)
    rows
  end

  def held_call(created_at:, resolved_at:)
    approval = @workspace.ability_approvals.create!(
      principal: @member, principal_label: "user:Alice Smith", action_key: "incidents.update", request_digest: SecureRandom.hex, required_role: "admin",
      status: Ability::Approval::STATUS_APPROVED, approver: workspace_memberships(:bob_workspace_one), held_for_run: true,
      run_expires_at: 52.minutes.from_now, resolved_at: resolved_at
    )
    held = Chat::HeldCall.create!(chat: @chat, approval: approval, tool_name: "resolve_incident", status: Chat::HeldCall::STATUS_READY)
    held.update_columns(created_at: created_at)
    held
  end

  def watch(at:, status: Chat::Watch::STATUS_ACTIVE)
    made = Chat::Watch.create!(chat: @chat, workspace: @workspace, asker: @member, title: "release run #{SecureRandom.hex(2)}", status: status,
                               expires_at: 40.minutes.from_now, usual_seconds: 18.minutes.to_i, limit_basis: Chat::Watch::BASIS_HISTORY)
    made.update_columns(created_at: at)
    made
  end

  def integration_tool
    @integration_tool ||= begin
      github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
      github.integration_environments.create!(base_config: { "installation_id" => "12345" })
      github.tools.create!(name: "set_actions_secret", read_only: false, enabled: true)
    end
  end

  # One chat is refused a pack once, so each refusal is for a pack of its own.
  def pack_request(key)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee #{key}", slug: "faylee_#{key}")
    northflank.tools.create!(name: "restart_service", read_only: false, enabled: true)
    Ability::PackRequest.for!(@member, northflank.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES))
  end

  def pull_request_notice
    session = CodeAgentSession.create!(workspace: @workspace, provider: "anthropic", model: "m", repository: "acme/api", budget_micros: 1,
                                       expires_at: 1.hour.from_now, token_digest: SecureRandom.hex, principal: @member, place: @conversation,
                                       pull_request_number: 689, pull_request_url: "https://github.com/acme/api/pull/689",
                                       pull_request_state: Integrations::PullRequests::OPEN)
    CodeAgentSession::Notice.create!(session: session, workspace: @workspace, conversation: @conversation, fingerprint: SecureRandom.hex, base: "main",
                                     status: CodeAgentSession::Notice::STATUS_OFFERED, problems: [ { "kind" => Integrations::PullRequests::PROBLEM_CONFLICT } ])
  end

  def code_pause(key, status: CodeAgentSession::Pause::STATUS_OFFERED)
    request = CodeAgent::Request.new(principal: @member, source: AbilityGateway::SOURCE_CONVERSATION, place: @conversation, tool_call_id: key)
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/api", request: request)
    CodeAgentSession::Pause.create!(session: session, workspace: @workspace, conversation: @conversation, arguments: { "repo" => "acme/api" },
                                    repository: "acme/api", base: "main", copy_ref: "c" * 40, budget_micros: 2_000_000,
                                    resumable_until: 15.minutes.from_now, status: status)
  end

  def database_tool
    @database_tool ||= begin
      planetscale = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale", slug: "planetscale",
                                                    settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
      planetscale.integration_environments.create!
      planetscale.tools.create!(name: "execute_write_query", description: "Write", enabled: true, read_only: false, params_schema: {})
    end
  end

  def data_repair(key)
    Chat::DataRepair.create!(chat: @chat, workspace: @workspace, asker: @member, tool_call_id: key, tool_name: database_tool.model_facing_name,
                             action_key: database_tool.action_key, table_name: "orders", rows_counted: 2,
                             statement_kind: Integrations::DataWrites::Statement::KIND_DELETE, status: Chat::DataRepair::STATUS_RAN)
  end

  def flag_tool
    @flag_tool ||= begin
      posthog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "posthog", name: "PostHog", slug: "posthog",
                                                settings: { "server_url" => "https://mcp.posthog.com/mcp?mode=tools" })
      posthog.integration_environments.create!
      posthog.tools.create!(name: "feature_flag_disable", description: "Disable a flag", enabled: true, read_only: false, params_schema: {})
    end
  end

  def mitigation(key)
    flag_tool
    Chat::Mitigation.create!(chat: @chat, workspace: @workspace, asker: @member, tool_call_id: key, tool_name: "posthog_feature_flag_disable",
                             action_key: "posthog.feature_flag_disable", target: "PostHog", duration_minutes: 60, status: Chat::Mitigation::STATUS_ACTIVE,
                             expires_at: 30.minutes.from_now, undo_state: Chat::Mitigation::UNDO_WRITING)
  end

  def chart
    points = (0..5).map { |minute| [ (START + minute.minutes).iso8601, minute ] }
    { "title" => "5xx of checkout", "unit" => "count", "from" => START.iso8601, "to" => (START + 5.minutes).iso8601,
      "series" => [ { "label" => "checkout", "points" => points } ] }
  end
end
