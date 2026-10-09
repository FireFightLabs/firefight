require "test_helper"

class Interactions::CodeQuestionHandlersTest < ActiveSupport::TestCase
  include CodeQuestionTestHelper
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    conversation = @workspace.conversations.create!(kind: Conversation::KIND_CHANNEL, started_by: @bob, channel_id: "C9", thread_id: "5.5",
                                                    max_turns: 5, max_spend_cents: 100)
    request = CodeAgent::Request.new(principal: @bob, source: AbilityGateway::SOURCE_CONVERSATION, place: conversation)
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/api", request: request)
    @question = ask_question!(session, "Tag or commit?")
    @question.update_columns(message_channel_id: "C9", message_id: "5.6")
    @adapter = @workspace.adapter
    Workspace.any_instance.stubs(:adapter).returns(@adapter)
    WorkspaceAdapter.stubs(:for).returns(@adapter)
  end

  test "Answer opens the form for the person the change runs as, and tells anyone else who can answer" do
    @adapter.expects(:open_code_question_modal).with(trigger_id: "T1", question: @question)
    Interactions::OpenCodeQuestionHandler.execute(button(@bob))

    @adapter.expects(:open_code_question_modal).never
    @adapter.expects(:post_ephemeral).with(channel_id: "C9", user_id: @alice.platform_user_id, text: "Only Bob Jones can answer, since the change runs as them.")
    Interactions::OpenCodeQuestionHandler.execute(button(@alice))
  end

  test "the form's answer reaches the agent and redraws the thread's message, and an empty one keeps the form open" do
    @adapter.expects(:update_code_question).with { |message_id:, question:, **| message_id == "5.6" && question.answer == "Send the tag." }.returns(success: true)

    assert_equal CodeAgentQuestionService::EMPTY, Interactions::AnswerCodeQuestionHandler.execute(submission("  "))[:errors][Slack::Modals::CodeQuestionAnswer::ANSWER_BLOCK]
    assert_nil Interactions::AnswerCodeQuestionHandler.execute(submission("Send the tag."))
    assert_equal [ CodeAgentQuestion::STATUS_ANSWERED, @bob ], [ @question.reload.status, @question.answered_by ]
  end

  test "the thread's message is the question in a line, then each option with its consequence and the recommended one with why, a button each and Something else" do
    blocks = Slack::Messages::CodeQuestion.build(@question)
    assert_equal ":question:  *The coding agent asks*", blocks.first.dig(:text, :text)
    assert_equal({ type: "divider" }, blocks.second)
    assert_equal "*Tag or commit?*", blocks.third.dig(:text, :text)
    assert_equal "*Send the tag*  ·  _Recommended. The release workflow already names its runs after the tag._\n" \
                 "Northflank names the run after the release, such as v1.4.0.", blocks.fourth.dig(:text, :text)
    assert_equal "*Send the commit*\nNorthflank names the run after the commit, such as 3f2a9c1.", blocks.fifth.dig(:text, :text)
    buttons = blocks.find { |block| block[:type] == "actions" }[:elements]
    assert_equal [ [ "Send the tag", Identifiers::CODE_QUESTION_CHOOSE_IDS.first, "#{@question.id}:0", "primary" ],
                   [ "Send the commit", Identifiers::CODE_QUESTION_CHOOSE_IDS.second, "#{@question.id}:1", nil ],
                   [ "Something else", Identifiers::CODE_QUESTION_ANSWER, @question.id, nil ] ],
                 buttons.map { |button| [ button.dig(:text, :text), button[:action_id], button[:value], button[:style] ] }
    assert_match "Only <@#{@bob.platform_user_id}> can answer.", blocks.last[:elements].sole[:text]
    assert_match "the change goes with the recommendation.", blocks.last[:elements].sole[:text]
    assert(blocks.none? { |block| block.dig(:text, :text).to_s.include?("\u2014") || block.dig(:text, :text).to_s.include?(";") })

    @question.answer!("Send the <!channel> tag.", by: @bob)
    settled = Slack::Messages::CodeQuestion.build(@question.reload)
    assert_equal ":question:  *The coding agent asked*", settled.first.dig(:text, :text)
    assert_equal "*Bob Jones* answered: Send the &lt;!channel&gt; tag.", settled.reverse.find { |block| block[:type] == "context" }[:elements].sole[:text]
    assert_equal [ [ "Change answer", Identifiers::CODE_QUESTION_CHANGE, @question.id ] ],
                 settled.select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }.map { |button| [ button.dig(:text, :text), button[:action_id], button[:value] ] }
  end

  test "an option's button answers in one click for the person the change runs as, and tells anyone else who can" do
    @adapter.expects(:post_ephemeral).with(channel_id: "C9", user_id: @alice.platform_user_id, text: "Only Bob Jones can answer, since the change runs as them.")
    assert_nil Interactions::ChooseCodeQuestionOptionHandler.execute(choice(@alice, 1))
    assert @question.reload.open?

    @adapter.expects(:update_code_question).with { |message_id:, question:, **| message_id == "5.6" && question.chosen == 1 }.returns(success: true)
    assert_nil Interactions::ChooseCodeQuestionOptionHandler.execute(choice(@bob, 1))

    assert_equal [ CodeAgentQuestion::STATUS_ANSWERED, 1, "Send the commit" ], @question.reload.values_at(:status, :chosen, :answer)
    assert_equal "Bob Jones chose: Send the commit. Northflank names the run after the commit, such as 3f2a9c1.", @question.agent_words
    assert_equal "*Bob Jones* chose Send the commit", Slack::Messages::CodeQuestion.build(@question).reverse.find { |block| block[:type] == "context" }[:elements].sole[:text]
  end

  test "Change answer opens the form for the person the change runs as while it is written, and tells anyone else why not" do
    @question.answer_as_halon!("The tag.", option: 0)
    @adapter.expects(:open_code_question_change_modal).with(trigger_id: "T1", question: @question)
    Interactions::OpenCodeQuestionChangeHandler.execute(change_button(@bob))

    @adapter.expects(:open_code_question_change_modal).never
    @adapter.expects(:post_ephemeral).with(channel_id: "C9", user_id: @alice.platform_user_id, text: "Only Bob Jones can change the answer, since the change runs as them.")
    Interactions::OpenCodeQuestionChangeHandler.execute(change_button(@alice))

    @question.session.close!
    @adapter.expects(:post_ephemeral).with(channel_id: "C9", user_id: @bob.platform_user_id,
                                           text: "The change this question was for has finished, so its answer can no longer change.")
    Interactions::OpenCodeQuestionChangeHandler.execute(change_button(@bob))
  end

  test "the change form offers the options and the person's own words, and its submission changes the answer and redraws the thread" do
    @question.answer_as_halon!("The tag.", option: 0)
    view = Slack::Modals::CodeQuestionChange.build(@question)
    assert_equal Identifiers::CODE_QUESTION_CHANGE_MODAL, view[:callback_id]
    radio = view[:blocks].find { |block| block[:block_id] == Slack::Modals::CodeQuestionChange::OPTION_BLOCK }
    assert_equal [ [ "Send the tag", "0" ], [ "Send the commit", "1" ] ], radio.dig(:element, :options).map { |option| [ option.dig(:text, :text), option[:value] ] }
    assert_match "The answer now: Send the tag", view[:blocks].find { |block| block[:type] == "context" }[:elements].sole[:text]

    assert_equal CodeAgentQuestionService::CHANGE_BOTH,
                 Interactions::ChangeCodeQuestionAnswerHandler.execute(change_submission(option: "1", answer: "Both."))[:errors][Slack::Modals::CodeQuestionChange::ANSWER_BLOCK]
    assert_equal CodeAgentQuestionService::SAME,
                 Interactions::ChangeCodeQuestionAnswerHandler.execute(change_submission(option: "0"))[:errors][Slack::Modals::CodeQuestionChange::ANSWER_BLOCK]

    @adapter.expects(:update_code_question).with { |message_id:, question:, **| message_id == "5.6" && question.changed_chosen == 1 }.returns(success: true)
    assert_nil Interactions::ChangeCodeQuestionAnswerHandler.execute(change_submission(option: "1"))
    assert_equal [ "Send the commit", @bob ], @question.reload.values_at(:changed_answer, :changed_by)

    blocks = Slack::Messages::CodeQuestion.build(@question)
    contexts = blocks.select { |block| block[:type] == "context" }.map { |block| block[:elements].sole[:text] }
    assert_equal [ "*Halon* chose Send the tag", "Changed to *Send the commit* by *Bob Jones*" ], contexts
    assert_match ":white_check_mark:  *Send the commit*", blocks.find { |block| block.dig(:text, :text).to_s.include?("Send the commit") }.dig(:text, :text)

    @question.session.close!
    assert(Slack::Messages::CodeQuestion.build(@question.reload).none? { |block| block[:type] == "actions" }, "no Change answer once the change finished")
  end

  test "the handlers declare a read to open the form and a write to change the answer" do
    assert_equal [ Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_READ ], Interactions::OpenCodeQuestionChangeHandler.authorization
    assert_equal [ Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE ], Interactions::ChangeCodeQuestionAnswerHandler.authorization
    assert_equal Interactions::OpenCodeQuestionChangeHandler, InteractionDispatcher::BLOCK_ACTION_HANDLERS.fetch(Identifiers::CODE_QUESTION_CHANGE)
  end

  private

  def change_button(member)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, trigger_id: "T1", channel_id: "C9",
                    user_id: member.platform_user_id, action_id: Identifiers::CODE_QUESTION_CHANGE, action_value: @question.id)
  end

  def change_submission(option: nil, answer: nil)
    values = { Slack::Modals::CodeQuestionChange::ANSWER_BLOCK => { Slack::Modals::CodeQuestionChange::ANSWER_INPUT => { "value" => answer } } }
    values[Slack::Modals::CodeQuestionChange::OPTION_BLOCK] = { Slack::Modals::CodeQuestionChange::OPTION_INPUT => { "selected_option" => { "value" => option } } } if option
    Interaction.new(
      platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, team_id: @workspace.platform_id, user_id: @bob.platform_user_id,
      callback_id: Identifiers::CODE_QUESTION_CHANGE_MODAL, private_metadata: ModalState.encode(code_question_id: @question.id), values: values
    )
  end

  def button(member)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, trigger_id: "T1", channel_id: "C9",
                    user_id: member.platform_user_id, action_id: Identifiers::CODE_QUESTION_ANSWER, action_value: @question.id)
  end

  def choice(member, index)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, trigger_id: "T1", channel_id: "C9",
                    user_id: member.platform_user_id, action_id: Identifiers::CODE_QUESTION_CHOOSE_IDS.fetch(index), action_value: "#{@question.id}:#{index}")
  end

  def submission(answer)
    Interaction.new(
      platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, team_id: @workspace.platform_id, user_id: @bob.platform_user_id,
      callback_id: Identifiers::CODE_QUESTION_MODAL, private_metadata: ModalState.encode(code_question_id: @question.id),
      values: { Slack::Modals::CodeQuestionAnswer::ANSWER_BLOCK => { Slack::Modals::CodeQuestionAnswer::ANSWER_INPUT => { "value" => answer } } }
    )
  end
end
