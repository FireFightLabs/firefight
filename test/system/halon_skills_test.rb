require "application_system_test_case"

class HalonSkillsTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    Investigation.stubs(:available_for?).returns(true)
    FeatureFlags.enable!(@workspace, FeatureFlags::CUSTOM_SKILLS)
    sign_in(users(:alice), @workspace)
  end

  def skill!(name = "game_day", steps: "1. Declare it with `declare_incident`.")
    Chat::CustomSkill.create_with!(workspace: @workspace, name: name, by: @alice,
                                   content: { "when" => "Someone asks for a game day", "tools" => [ "declare_incident" ], "steps" => steps })
  end

  test "a skill is written in the dialog with its tools, says so, and is listed with its version" do
    visit halon_skills_path
    assert_text "No skills of your own yet"

    click_button "New skill"
    fill_in "Name", with: "rotate_keys"
    fill_in "When Halon uses it", with: "Someone asks to rotate the API keys"
    click_button "Choose the tools its steps call"
    find("[cmdk-input]").fill_in(with: "declare_incident")
    find("[cmdk-item]", text: "declare_incident").click
    find("body").send_keys(:escape)
    find(".ProseMirror").click
    find(".ProseMirror").send_keys("Declare a maintenance incident first.")
    click_button "Add skill"

    assert_toast "rotate_keys was added. Halon can load it from its next question."
    assert_text "Version 1"
    skill = Chat::CustomSkill.find_by!(workspace: @workspace, name: "rotate_keys")
    assert_equal [ "declare_incident" ], skill.live_version.tools
  end

  test "one of Firefight's skills is read and copied, and the copy is listed as Firefight's" do
    visit halon_skills_path

    fill_in "Search skills", with: "declaring"
    click_button "declaring"
    assert_text "Firefight's skill, version"
    assert_text "Do not call anything else to find the severities or types"
    click_button "Copy to change it"

    assert_toast "declaring was copied. Halon uses your copy in place of Firefight's from now on."
    assert_text "Copy of Firefight's, version"
    assert Chat::CustomSkill.exists?(workspace: @workspace, name: "declaring", library_name: "declaring")
  end

  test "a skill a workflow runs cannot be deleted, and one that none runs is deleted after asking" do
    used = skill!
    Workflow.create!(workspace: @workspace, name: "Drill").open_draft!(by: @alice)
            .update_columns(steps: [ { "id" => "step_1", "name" => "drill", "kind" => "run_skill", "config" => { "skill" => used.name } } ])
    skill!("spare")

    visit halon_skills_path
    find("button", text: "Actions for game_day").click
    assert_selector "[role=menuitem][data-disabled]", text: "Delete"
    find("body").send_keys(:escape)

    find("button", text: "Actions for spare").click
    find("[role=menuitem]", text: "Delete").click
    assert_text "spare and its 1 version are deleted"
    within("[role=dialog]") { click_button "Delete" }

    assert_toast "spare was deleted. Halon no longer loads it."
    assert Chat::CustomSkill.exists?(used.id)
  end

  test "a skill a workflow runs is turned off after reading what that stops, and on again, each saying so" do
    skill = skill!
    Workflow.create!(workspace: @workspace, name: "Drill").open_draft!(by: @alice)
            .update_columns(steps: [ { "id" => "step_1", "name" => "drill", "kind" => "run_skill", "config" => { "skill" => skill.name } } ])

    visit halon_skills_path
    find("[role=switch][aria-label='game_day is on']").click
    assert_text "1 workflow runs game_day. While it is off, their step that runs it fails"
    within("[role=dialog]") { click_button "Turn off" }

    assert_toast "game_day is off. Halon no longer loads it"
    assert_not skill.reload.enabled?

    find("[role=switch][aria-label='game_day is off']").click
    assert_toast "game_day is on. Halon loads it again."
    assert skill.reload.enabled?
  end

  test "an earlier version is brought back from the history" do
    skill = skill!
    skill.write!(skill.live_version.content.merge("steps" => "1. Something else with `declare_incident`."), by: @alice, reason: "Tried another way.")

    visit halon_skills_path
    find("button", text: "Actions for game_day").click
    find("[role=menuitem]", text: "History").click
    assert_text "Tried another way."
    click_button "Bring back version 1"

    assert_toast "game_day says what version 1 said again, as version 3."
  end

  test "Halon's proposal shows what it changes and is accepted from the page" do
    skill!
    Chat::CustomSkill.propose_for!(@workspace, name: "game_day", reason: "The team pages before declaring.",
                                               content: { "when" => "Someone asks for a game day", "tools" => %w[declare_incident escalate_incident],
                                                          "steps" => "1. Page first with `escalate_incident`, then `declare_incident`." })

    visit halon_skills_path
    assert_text "Proposed by Halon"
    assert_text "The team pages before declaring."
    assert_text "escalate_incident"
    click_button "Accept change"

    assert_toast "game_day was updated. Halon loads it as it now reads."
    assert_no_text "Proposed by Halon"
  end

  test "a copy is told of Firefight's newer version and takes it after reading what changed" do
    library = Chat::Skill.find("declaring")
    Chat::CustomSkill.copy!(library, workspace: @workspace, by: @alice)
    newer = library.with(version: library.version + 1, steps: "#{library.steps}\n9. Say in the channel that it is declared.")
    Chat::Skill.stubs(:find).returns(nil)
    Chat::Skill.stubs(:find).with("declaring").returns(newer)

    visit halon_skills_path
    click_button "Version #{newer.version} is out"
    assert_text "Your copy stays as it is until you choose."
    click_button "Take Firefight's version"

    assert_toast "declaring now says what Firefight's version #{newer.version} says."
  end

  test "Halon's proposal in a chat is a card that accepts it" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    Chat::CustomSkill.propose_for!(@workspace, name: "rotate_keys", reason: "You rotated keys this way twice.", conversation: conversation,
                                               content: { "when" => "Someone asks to rotate keys", "tools" => [ "declare_incident" ], "steps" => "1. Declare with `declare_incident`." })

    visit agent_chat_path(conversation)
    assert_text "Add the skill rotate_keys?"
    watch_page
    click_button "Add skill"

    assert_toast "rotate_keys was added. Halon loads it as it now reads."
    assert_text "Accepted by"
    assert_stayed_in_place(only: AgentChatsController::PROP_SKILL_PROPOSALS)
  end
end
