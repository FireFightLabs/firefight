require "test_helper"

# Several people can ask Halon in one incident thread. Halon has to tell them apart, know whose direction wins, and hear
# how the handbook edits it proposed were settled.
class Conversation::DirectingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @thread = @workspace.conversations.create!(subject: @incident, kind: Conversation::KIND_CHANNEL, channel_id: @incident.channel_id,
                                               thread_id: "1.1", started_by: @alice, max_turns: 10, max_spend_cents: 50)
    RubyLLM.config.stubs(:openai_api_key).returns("not-used")
  end

  test "in an incident's thread the model reads each person's message headed with who wrote it, which is kept apart from their words" do
    @thread.ask!("roll back checkout", asker: @alice)
    @thread.reply_delivered!
    @thread.ask!("do not roll back, it is the database", asker: @bob)

    said = @thread.chat_record.reload.to_llm.messages.select { |message| message.role == :user }.map(&:content)

    assert_equal [ "#{@alice.display_name} wrote:\nroll back checkout", "#{@bob.display_name} wrote:\ndo not roll back, it is the database" ], said
    assert_equal [ "roll back checkout", "do not roll back, it is the database" ], @thread.chat.messages.where(role: Chat::Message::ROLE_USER).map(&:content)
    assert_equal [ @alice, @bob ], @thread.chat.messages.where(role: Chat::Message::ROLE_USER).map(&:sender)
  end

  test "a message sent while Halon works reaches the model headed with its sender too" do
    @thread.ask!("check the logs", asker: @alice)
    @thread.update!(answer_owed_since: Time.current)
    @thread.ask!("and the deploys", asker: @bob)
    chat = @thread.chat_record
    chat.to_llm

    chat.take_queued!(from: @bob)

    assert_equal "#{@bob.display_name} wrote:\nand the deploys", chat.to_llm.messages.last.content
  end

  test "a dashboard chat has one person, so their messages read as they wrote them" do
    personal = Conversation.start_personal!(workspace: @workspace, member: @alice)
    personal.ask!("what is slow", asker: @alice)

    assert_equal "what is slow", personal.chat_record.reload.to_llm.messages.find { |message| message.role == :user }.content
  end

  test "in an incident's thread Halon is told it takes direction from whoever holds the role the handbook names" do
    @incident.assign_role!(incident_roles(:incident_lead_ws1), @alice)

    assert_equal "Several people can write to you in this thread, and each message starts with who wrote it. In #{@incident.identifier} you take " \
                 "direction from #{@alice.display_name}, who holds Incident Lead.", directing_line(@thread)

    handbook_page!(@workspace, Chat::HandbookPage::DIRECTING_TITLE, "", role: incident_roles(:communications_lead_ws1))
    assert_match "from #{@bob.display_name}, who holds Communications Lead.", directing_line(@thread)
  end

  test "with nobody in the role Halon asks the people there to assign it before acting on conflicting directions" do
    assert_match "whoever holds Incident Lead, which nobody holds yet, so ask the people here to assign it", directing_line(@thread)
  end

  test "a dashboard chat names no director" do
    assert_nil directing_line(Conversation.start_personal!(workspace: @workspace, member: @alice))
  end

  test "a run's notes say who added them and the roles they hold, and its facts name who directs it" do
    @incident.assign_role!(incident_roles(:incident_lead_ws1), @alice)
    run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)
    run.add_note!("roll back checkout", by: @alice)
    run.add_note!("do not roll back", by: @bob)

    notes = run.take_notes!.map { |note| run.chat.messages.find_by!(sender: note.sender).content }

    assert_equal [ "#{@alice.display_name} (Incident Lead) added: roll back checkout", "#{@bob.display_name} (Communications Lead) added: do not roll back" ], notes
    facts = Investigation::IncidentSeed.new(run).send(:incident_facts)
    assert_equal({ "role" => "Incident Lead", "member" => { "name" => @alice.display_name } }, facts["directs_halon"])
  end

  test "a chat hears once how each handbook edit it proposed was settled" do
    page = handbook_page!(@workspace, "How we release", "Run the release pipeline")
    proposal = Chat::HandbookProposal.propose!(@thread, page: page, text: "Run the deploy workflow", evidence: "Runs show it.")
    proposal.dismiss!(by: @bob)
    chat = @thread.chat_record

    runner = Conversation::Runner.new(@thread, asker: @alice)
    2.times { runner.send(:tell_held_outcomes, chat) }

    told = chat.messages.where(nudge: true).map(&:content)
    assert_equal [ "#{@bob.display_name} dismissed your proposed edit to the handbook page How we release. Keep following the handbook as written, and do not propose the same again." ], told
  end

  private

  def directing_line(conversation) = Conversation::Runner.new(conversation, asker: @alice).send(:directing_line)
end
