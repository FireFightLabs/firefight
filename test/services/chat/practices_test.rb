require "test_helper"

# Halon's standing instructions teach practice (FirefightAi::Manual), and the playbooks teach one area each. What one
# tool needs is said by that tool, where Halon meets it. Each test here pins a rule the old instructions carried to the
# place it moved to.
class Chat::PracticesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @turn = Conversation::Turn.new(@conversation, asker: @member)
  end

  test "every playbook the manual names is one of Firefight's skills, and every playbook is named" do
    playbooks = Chat::Skill.all.select { |skill| skill.firefight? && skill.domain == Chat::Skill::DOMAIN_PLAYBOOKS }

    assert_equal FirefightAi::Manual::PLAYBOOK_NAMES.sort, playbooks.map(&:name).sort
  end

  test "each playbook says what good looks like, how to approach it, what to check, its trade-offs and when it is done" do
    FirefightAi::Manual::PLAYBOOK_NAMES.each do |name|
      steps = Chat::Skill.find(name).steps
      [ "What good looks like:", "How to approach it:", "What to check:", "Trade-offs:", "Done means:", "Proactive habits:" ].each do |part|
        assert_includes steps, part, "#{name} says #{part}"
      end
      assert_no_match(/[—;]/, steps, "#{name} has an em dash or a semicolon")
    end
  end

  test "the version Halon's prompts record includes every playbook's words" do
    assert_equal Chat::Skill.playbooks_text, FirefightAi.configuration.playbooks.call
    FirefightAi::Manual::PLAYBOOK_NAMES.each { |name| assert_includes Chat::Skill.playbooks_text, Chat::Skill.find(name).steps }
    refute_equal FirefightAi::Prompt.version(FirefightAi::Investigator.system_prompt), FirefightAi::Investigator.prompt_version
  end

  test "a playbook loads through use_skill like any skill, and hands over the tools it names" do
    offered = []
    use_skill = Chat::Tools::UseSkill.new(@turn, offer: ->(tools) { offered.concat(tools) })

    assert_includes use_skill.description, "firefight playbooks:\ncapacity:"
    answer = use_skill.call("skill" => "incident_command")

    assert_includes answer, Chat::Skill.find("incident_command").steps
    assert_includes offered.map(&:name), Mcp::Tools::GET_INCIDENT
  end

  test "the rules the playbooks took over are in them" do
    assert_match "read their names and columns from the application's repository", Chat::Skill.find("data").steps
    assert_match "Read the primary first", Chat::Skill.find("data").steps
    assert_match "read that system's documented contract", Chat::Skill.find("code").steps
    assert_match "check that everything running before it", Chat::Skill.find("code").steps
    assert_match "an error printed every day is not taken for the cause", Chat::Skill.find("monitoring").steps
    assert_match "`check_status_page` reads that provider's status before you blame the team's code", Chat::Skill.find("monitoring").steps
    assert_match "`blind_spots` names it", Chat::Skill.find("monitoring").steps
    assert_match "A trend needs more than one reading", Chat::Skill.find("proactive_hygiene").steps
  end

  test "a plan's rules are in its tools and in the plans Halon reads each turn" do
    assert_match "say the plan back in two short lines and start", Conversation::Tools::MakePlan.new(@turn).description
    assert_match "A time inside a freeze is refused", Conversation::Tools::MakePlan.new(@turn).description
    update = Conversation::Tools::UpdatePlan.new(@turn).description
    assert_match "resource_status and its error rate and p95 latency with run_key_query", update
    assert_match "offer to retry or undo", update
    assert_match "say where things stand against its goal in every report", Conversation::Plans.for_halon(plan_chat)
  end

  test "following, saving and starting work is said by the tools that do it" do
    assert_match "is yours to follow: start a watch on it in the same turn", Conversation::Tools::StartWatch.new(@turn).description
    assert_match "offer to save it as a runbook", Conversation::Tools::RunRunbook.new(@turn).description
    assert_match "offer to run it again and start it yourself once the person agrees", Conversation::Tools::StartInvestigation.new(@turn).description
    assert_match "Keep for yourself anything that changes something", Chat::Tools::Helpers.new(@turn, share: nil).description
  end

  test "how to reach a provider is said by the tools that read it" do
    assert_match "its skill, guides and search_docs come first", Chat::Tools::Web.new(@turn, Chat::Tools::Web::SEARCH).description
    assert_match "A read that fails on a path the key reads do not list answers with the nearest ones they do", Integrations::ApiReads::PATH_PARAMS.dig("path", "description")
    assert_match "look here before asking a person", Mcp::Tools::GetResourceMap.description_value
    assert_match "before blaming the team's own code", Mcp::Tools::CheckStatusPage.description_value
    assert_match "rather than guessing what it did", Mcp::Tools::BlindSpots.description_value
    assert_match "Use it first when asked what changed before something broke", ResourceMap::Timeline::DESCRIPTION
    assert_match "a line that was always there is not taken for the cause", ResourceMap::LogTemplate::DESCRIPTION
    assert_match "When one is pasted, say it was not used", Mcp::Tools::ListIntegrations.description_value
    assert_match "it wins over what a provider says it serves", Chat::Tools::OutsideCheck.new(@turn).description
    assert_match "Use it for a report that a page or button does not work, and to confirm a page works after a change",
                 Chat::Tools::Browser.new(@turn).description
  end

  test "what a failed call means is said after the provider's words" do
    assert_match "correct that part and send the change again", Chat::Tools::Connection::CHANGE_FAILED
    assert_match "stays asked for while they add other requests", Chat::Tools::Connection::CHANGE_FAILED
    assert_match "is the provider's suggestion for that one call, and what the person asked for may not need it", Chat::Tools::Connection::CHANGE_FAILED
    assert_match "the data may still be reachable another way", Chat::Tools::Connection::READ_FAILED
    assert_match "Say so in your answer, with what you did instead", Chat::Tools::Connection::TIMED_OUT
    assert_match "Tell the person plainly that a Firefight rule refused it", FirefightAi::Evidence::REFUSED_BY_RULE
  end

  test "a run's answer and a check's notes say what each takes" do
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                      max_turns: 10, max_spend_cents: 400)
    conclude = Investigation::Tools::Conclude.new(investigation)
    assert_match "When the evidence supports no cause, conclude saying so", conclude.description
    assert_match "the next apply would undo a direct change", conclude.parameters_schema.dig("properties", "fix", "description")
    assert_match "as soon as you have one", Investigation::Tools::RecordHypothesis.new(investigation).description
    assert_match "Something fine, or that needs no one to act, stays out of the notes", Investigation::Tools::NoteProblem.new(investigation).description
    assert_match "never as fine", Investigation::Tools::FinishCheck.new(investigation).parameters_schema.dig("properties", "gaps", "description")
  end

  test "the parts of a run's facts the engine explains are the parts the app writes under those names" do
    written = [ Investigation::Seeding::KEY_HANDBOOK, Investigation::Seeding::KEY_INSTRUCTIONS, Investigation::Seeding::KEY_MEMORIES,
                Investigation::Seeding::KEY_ON_CALL ]

    written.each { |key| assert_includes FirefightAi::Facts::READING.keys, key }
  end

  test "who directs Halon, the handbook, instructions and memory say how to use them where Halon reads them" do
    assert_match "propose the edit with propose_handbook_edit", Chat::HandbookPage::HANDBOOK_HEADING
    assert_match "ask them to decide before you change anything", Chat::HandbookPage::CONFLICTING
  end

  test "a code change's answer says what to tell the person, and its brief cites the contract" do
    assert_match "what review found and could not verify", Integrations::CodeWriteUp::TELLING
    assert_includes Integrations::CodeWriteUp::TELLING, FirefightAi::Copy::NOT_RUN
  end

  private

  def plan_chat
    chat = @conversation.chat_record
    steps = [ { "kind" => "read", "description" => "Read the latest commit on main" }, { "kind" => "read", "description" => "Read the release run" } ]
    Chat::Plan.make!(chat: chat, made_by: @member, goal: "Find what the release shipped", steps: steps)
    chat
  end
end
