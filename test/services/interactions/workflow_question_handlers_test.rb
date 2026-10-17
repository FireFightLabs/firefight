require "test_helper"

class Interactions::WorkflowQuestionHandlersTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  QUIET = [ WriteSearchEmbeddingJob, SearchDocumentIndexJob, InvestigationJob ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @adapter = @workspace.adapter
    Workspace.any_instance.stubs(:adapter).returns(@adapter)
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    @adapter.stubs(:post_workflow_question).returns({ channel_id: "D-BOB", message_id: "1.1" })
    Slack::DashboardUrl.stubs(:workflow_run).returns("https://firefight.test/halon/workflows/run")
    stub_successful_slack_workflow
  end

  def asked(config)
    workflow = Workflow.create!(workspace: @workspace, name: "Release", created_by: @alice)
    draft = workflow.open_draft!(by: @alice)
    ask = { "id" => "ask", "name" => "ask", "kind" => "ask_person", "config" => { "to" => "person", "person" => "bob@example.com", "question" => "Ship the <!channel> fix?" }.merge(config) }
    draft.update!(trigger: { "kind" => "manual", "inputs" => [] }, steps: [ ask ], edges: [])
    assert WorkflowPublishService.new(workflow).publish!(draft.reload, by: @alice).ok
    run = nil
    perform_enqueued_jobs(except: QUIET) { run = WorkflowRunService.new(workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice) }
    @run = run.reload
    @question = @run.steps.find_by!(step_key: "ask").questions.sole
  end

  test "the direct message is the question, a button per choice and the run, and once answered it says who answered and how" do
    asked("choices" => %w[ship_it wait], "details" => "The fix is merged.")

    blocks = Slack::Messages::WorkflowQuestion.build(@question)
    assert_equal ":question:  *Release asks*", blocks.first.dig(:text, :text)
    assert_equal "*Ship the &lt;!channel&gt; fix?*", blocks.third.dig(:text, :text)
    assert_equal "> The fix is merged.", blocks.fourth.dig(:text, :text)
    buttons = blocks.find { |block| block[:type] == "actions" }[:elements]
    assert_equal [ [ "Ship it", Identifiers::WORKFLOW_QUESTION_CHOOSE_IDS.first, "#{@question.id}:0" ], [ "Wait", Identifiers::WORKFLOW_QUESTION_CHOOSE_IDS.second, "#{@question.id}:1" ] ],
                 buttons.first(2).map { |button| [ button.dig(:text, :text), button[:action_id], button[:value] ] }
    assert_equal "Open the run", buttons.last.dig(:text, :text)
    assert_match "<@#{@bob.platform_user_id}> can answer, and the first answer counts.", blocks.last[:elements].sole[:text]
    words = blocks.map { |block| block.dig(:text, :text).to_s.gsub(/&\w+;/, "") }
    assert(words.none? { |text| text.include?("\u2014") || text.include?(";") })

    @adapter.expects(:post_ephemeral).with(channel_id: "D-BOB", user_id: @alice.platform_user_id, text: "Only #{@bob.actor_display_name} can answer this.")
    assert_nil Interactions::ChooseWorkflowAnswerHandler.execute(choice(@alice, 0))

    @adapter.expects(:update_workflow_question).with { |message_id:, question:, **| message_id == "1.1" && question.answered? }.returns(success: true)
    perform_enqueued_jobs(except: QUIET) { assert_nil Interactions::ChooseWorkflowAnswerHandler.execute(choice(@bob, 0)) }
    assert_equal "ship_it", @question.reload.answer["choice"]
    assert_equal "ship_it", @run.reload.steps.find_by!(step_key: "ask").route

    settled = Slack::Messages::WorkflowQuestion.build(@question)
    assert_equal ":question:  *Release asked*", settled.first.dig(:text, :text)
    assert_equal "*#{@bob.actor_display_name}* answered: Ship it", settled.last[:elements].sole[:text]
    assert_equal [ "Open the run" ], settled.select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }.map { |button| button.dig(:text, :text) }
  end

  test "Answer opens the form for someone asked, whose submission answers it, and tells anyone else who can" do
    asked("choices" => %w[ship_it wait], "fields" => [ { "name" => "why", "label" => "Why" } ])
    assert_equal [ "Answer", "Open the run" ], Slack::Messages::WorkflowQuestion.build(@question).find { |block| block[:type] == "actions" }[:elements].map { |button| button.dig(:text, :text) }

    @adapter.expects(:open_workflow_question_modal).never
    @adapter.expects(:post_ephemeral).with(channel_id: "D-BOB", user_id: @alice.platform_user_id, text: "Only #{@bob.actor_display_name} can answer this.")
    Interactions::OpenWorkflowQuestionHandler.execute(button(@alice))

    @adapter.unstub(:open_workflow_question_modal)
    @adapter.expects(:open_workflow_question_modal).with(trigger_id: "T1", question: @question)
    Interactions::OpenWorkflowQuestionHandler.execute(button(@bob))

    view = Slack::Modals::WorkflowQuestionAnswer.build(@question)
    assert_equal Identifiers::WORKFLOW_QUESTION_MODAL, view[:callback_id]
    assert_equal [ Slack::Modals::WorkflowQuestionAnswer::CHOICE_BLOCK, "field_why" ], view[:blocks].filter_map { |block| block[:block_id] }

    refused = Interactions::AnswerWorkflowQuestionHandler.execute(submission(choice: nil, why: "Because."))
    assert_equal "Pick one of the choices.", refused[:errors][Slack::Modals::WorkflowQuestionAnswer::CHOICE_BLOCK]

    @adapter.stubs(:update_workflow_question).returns(success: true)
    perform_enqueued_jobs(except: QUIET) { assert_nil Interactions::AnswerWorkflowQuestionHandler.execute(submission(choice: "wait", why: "The deploy window is closed.")) }
    assert_equal({ "choice" => "wait", "fields" => { "why" => "The deploy window is closed." } }, @question.reload.answer)
    assert_equal "The deploy window is closed.", @run.reload.steps.find_by!(step_key: "ask").output["why"]
  end

  test "the handlers read workflows and are wired to their ids" do
    assert_equal [ Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_READ ], Interactions::ChooseWorkflowAnswerHandler.authorization
    assert_equal Interactions::OpenWorkflowQuestionHandler, InteractionDispatcher::BLOCK_ACTION_HANDLERS.fetch(Identifiers::WORKFLOW_QUESTION_ANSWER)
    assert_equal Interactions::ChooseWorkflowAnswerHandler, InteractionDispatcher::BLOCK_ACTION_HANDLERS.fetch(Identifiers::WORKFLOW_QUESTION_CHOOSE_IDS.last)
    assert_equal Interactions::AnswerWorkflowQuestionHandler, InteractionDispatcher::VIEW_SUBMISSION_HANDLERS.fetch(Identifiers::WORKFLOW_QUESTION_MODAL)
  end

  private

  def button(member)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, trigger_id: "T1", channel_id: "D-BOB",
                    user_id: member.platform_user_id, action_id: Identifiers::WORKFLOW_QUESTION_ANSWER, action_value: @question.id)
  end

  def choice(member, index)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, trigger_id: "T1", channel_id: "D-BOB",
                    user_id: member.platform_user_id, action_id: Identifiers::WORKFLOW_QUESTION_CHOOSE_IDS.fetch(index), action_value: "#{@question.id}:#{index}")
  end

  def submission(choice:, why:)
    values = { "field_why" => { Slack::Modals::WorkflowQuestionAnswer::FIELD_INPUT => { "value" => why } } }
    values[Slack::Modals::WorkflowQuestionAnswer::CHOICE_BLOCK] = { Slack::Modals::WorkflowQuestionAnswer::CHOICE_INPUT => { "selected_option" => { "value" => choice } } } if choice
    Interaction.new(platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, team_id: @workspace.platform_id, user_id: @bob.platform_user_id,
                    callback_id: Identifiers::WORKFLOW_QUESTION_MODAL, private_metadata: ModalState.encode(workflow_question_id: @question.id), values: values)
  end
end
