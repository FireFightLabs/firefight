require "test_helper"

class HalonSkillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    sign_in(users(:alice), @workspace)
  end

  def content(steps: "1. Declare it with `declare_incident`.")
    { "when" => "Someone asks for a game day", "tools" => [ "declare_incident" ], "steps" => steps }
  end

  def skill!(name = "game_day")
    Chat::CustomSkill.create_with!(workspace: @workspace, name: name, content: content, by: @alice)
  end

  test "the page lists the workspace's skills, Halon's proposals and Firefight's library" do
    skill!
    Chat::CustomSkill.propose_for!(@workspace, name: "rotate_keys", content: content, reason: "Asked twice this week.")

    get halon_skills_path, headers: inertia_headers

    assert_equal "halon/skills", JSON.parse(response.body)["component"]
    assert_equal [ [ "game_day", 1, "Someone asks for a game day" ] ], inertia_props["skills"].map { |skill| skill.values_at("name", "version", "usedWhen") }
    assert_equal [ "rotate_keys", true, "Asked twice this week." ], inertia_props["proposals"].sole.values_at("name", "newSkill", "reason")
    declaring = inertia_props["library"].find { |skill| skill["name"] == "declaring" }
    assert_equal [ "Firefight", false, nil ], declaring.values_at("source", "copied", "steps")
    assert_nil inertia_props["toolChoices"]
  end

  test "the editor's tools, a library skill's steps and a skill's history load when asked for" do
    skill = skill!
    skill.write!(content(steps: "1. Ask first, then `declare_incident`."), by: @alice, reason: "Ask first.")

    get halon_skills_path(library: "declaring", history: skill.id),
        headers: inertia_headers.merge("X-Inertia-Partial-Component" => "halon/skills", "X-Inertia-Partial-Data" => "toolChoices,librarySkill,history")

    assert_includes inertia_props["toolChoices"].map { |choice| choice["name"] }, "declare_incident"
    assert_includes inertia_props["toolChoices"].map { |choice| choice["name"] }, Chat::Tools::WhatChanged::NAME
    assert_equal Chat::Skill.find("declaring").steps, inertia_props["librarySkill"]["steps"]
    assert_equal [ [ 2, "live", "Ask first.", "This is the live version." ], [ 1, "retired", nil, nil ] ],
                 inertia_props["history"].map { |version| version.values_at("number", "status", "reason", "restoreBlockedReason") }
  end

  test "a skill is created, edited, restored and deleted, each saying so" do
    post halon_skills_path, params: { name: "game_day", when: "Someone asks for a game day", tools: [ "declare_incident" ], steps: "1. Declare." }
    skill = Chat::CustomSkill.find_by!(workspace: @workspace, name: "game_day")
    assert_equal "game_day was added. Halon can load it from its next question.", flash[:notice]

    patch halon_skill_path(skill), params: { name: "game_day", when: "A drill", tools: [ "declare_incident" ], steps: "1. Declare it.",
                                             reason: "Shorter.", seen_version_id: skill.live_version_id }
    assert_equal "game_day was updated to version 2.", flash[:notice]

    post restore_halon_skill_path(skill), params: { version_id: skill.versions.find_by!(number: 1).id }
    assert_equal "game_day says what version 1 said again, as version 3.", flash[:notice]
    assert_equal "1. Declare.", skill.reload.live_version.steps

    delete halon_skill_path(skill)
    assert_equal "game_day was deleted. Halon no longer loads it.", flash[:notice]
    assert_not Chat::CustomSkill.exists?(skill.id)
  end

  test "a save over a version someone replaced is refused, and the form keeps what was written" do
    skill = skill!
    seen = skill.live_version_id
    skill.write!(content(steps: "1. Bob's."), by: workspace_memberships(:bob_workspace_one))

    patch halon_skill_path(skill), params: { name: "game_day", when: "x", tools: [], steps: "1. Mine.", seen_version_id: seen }

    assert_equal [ Chat::CustomSkill::Writing::CHANGED_FIRST ], session["inertia_errors"][:base]
    assert_equal "1. Bob's.", skill.reload.live_version.steps
  end

  test "a field that does not hold is named beside it" do
    post halon_skills_path, params: { name: "game_day", when: "", tools: [ "declare_incident" ], steps: "1. Go." }
    assert_equal [ "should say when Halon uses it" ], session["inertia_errors"][:when]

    post halon_skills_path, params: { name: "game_day", when: "A drill", tools: [ "launch_rockets" ], steps: "1. Go." }
    assert_equal [ "launch_rockets is not a tool Halon has in this workspace." ], session["inertia_errors"][:tools]
    assert_not Chat::CustomSkill.exists?(name: "game_day")
  end

  test "a skill a workflow runs is not deleted, with why" do
    skill = skill!
    Workflow.create!(workspace: @workspace, name: "Drill").open_draft!(by: @alice)
            .update_columns(steps: [ { "id" => "step_1", "name" => "drill", "kind" => "run_skill", "config" => { "skill" => "game_day" } } ])

    delete halon_skill_path(skill)

    assert_match "1 workflow runs game_day", flash[:alert]
    assert Chat::CustomSkill.exists?(skill.id)
  end

  test "one of Firefight's skills is copied, exported, and the copy takes or keeps a newer library version" do
    post copy_halon_library_skill_path("declaring")
    copy = Chat::CustomSkill.find_by!(workspace: @workspace, name: "declaring")
    assert_equal "declaring was copied. Halon uses your copy in place of Firefight's from now on.", flash[:notice]

    post copy_halon_library_skill_path("declaring")
    assert_equal "You already have a copy of declaring, under Your skills.", flash[:alert]

    library = Chat::Skill.find("declaring")
    newer = library.with(version: library.version + 1, steps: "#{library.steps}\n9. Done.")
    Chat::Skill.stubs(:find).with("declaring").returns(newer)

    get halon_skills_path, headers: inertia_headers
    assert_equal newer.version, inertia_props["skills"].sole["libraryUpdate"]["version"]

    post keep_own_halon_skill_path(copy)
    assert_equal "declaring keeps your words. You are told again when Firefight ships a newer version.", flash[:notice]
    copy.reload.update!(library_dismissed_version: nil)

    post take_library_halon_skill_path(copy)
    assert_equal "declaring now says what Firefight's version #{newer.version} says.", flash[:notice]
    assert_equal newer.steps, copy.reload.live_version.steps

    get export_halon_skill_path(copy)
    assert_equal "text/markdown", response.media_type
    assert_includes response.body, "name: declaring"
    assert_match "SKILL.md", response.headers["Content-Disposition"]

    delete halon_skill_path(copy)
    assert_equal "declaring was deleted. Halon uses Firefight's declaring again.", flash[:notice]
  end

  test "a SKILL.md file is imported as a new skill, and again as the next version of the same skill" do
    file = Rack::Test::UploadedFile.new(StringIO.new(Chat::CustomSkill::Document.render(skill!("drill").definition).sub("name: drill", "name: Game-Day")),
                                        "text/markdown", original_filename: "SKILL.md")

    post import_halon_skills_path, params: { file: file }
    assert_equal "game_day was imported. Halon can load it from its next question.", flash[:notice]

    file.rewind
    post import_halon_skills_path, params: { file: file }
    assert_equal "game_day was updated from the file, as version 2.", flash[:notice]

    post import_halon_skills_path, params: { file: Rack::Test::UploadedFile.new(StringIO.new("just words"), "text/markdown", original_filename: "SKILL.md") }
    assert_match "no front matter", session["inertia_errors"][:file].sole
  end

  test "a SKILL.md named for a skill only Halon has proposed becomes that skill, and the proposal waits to be edited or dismissed" do
    proposal = Chat::CustomSkill.propose_for!(@workspace, name: "rotate_keys", content: content, reason: "Asked twice.")
    text = "---\nname: rotate_keys\nwhen: Someone asks to rotate keys\ntools: [declare_incident]\n---\n1. Our way with `declare_incident`.\n"

    post import_halon_skills_path, params: { file: Rack::Test::UploadedFile.new(StringIO.new(text), "text/markdown", original_filename: "SKILL.md") }

    assert_equal "rotate_keys was imported. Halon can load it from its next question.", flash[:notice]
    skill = proposal.custom_skill.reload
    assert_equal "1. Our way with `declare_incident`.", skill.live_version.steps
    assert proposal.reload.proposed?
    assert_match "changed since Halon proposed this", skill.accept_blocked_reason(proposal)
  end

  test "Halon's proposal is accepted as written, edited first or dismissed" do
    skill = skill!
    proposal = Chat::CustomSkill.propose_for!(@workspace, name: "game_day", content: content(steps: "1. Page first, then `declare_incident`."), reason: "Seen.")
    post accept_halon_skill_proposal_path(proposal)
    assert_equal "game_day was updated. Halon loads it as it now reads.", flash[:notice]
    assert_equal proposal, skill.reload.live_version

    second = Chat::CustomSkill.propose_for!(@workspace, name: "game_day", content: content(steps: "1. Halon's."), reason: "Seen again.")
    post accept_halon_skill_proposal_path(second), params: { name: "game_day", when: "A drill", tools: [ "declare_incident" ], steps: "1. Mine." }
    assert_equal "game_day was updated with your edit. Halon loads it as it now reads.", flash[:notice]
    assert_equal "1. Mine.", skill.reload.live_version.steps

    third = Chat::CustomSkill.propose_for!(@workspace, name: "rotate_keys", content: content, reason: "Asked.")
    post dismiss_halon_skill_proposal_path(third)
    assert_equal "Halon's proposed rotate_keys was dismissed. Your skills are unchanged.", flash[:notice]
  end

  test "a member reads the skills and needs a grant to change them" do
    sign_in(users(:bob), @workspace)

    get halon_skills_path, headers: inertia_headers
    assert_equal "halon/skills", JSON.parse(response.body)["component"]

    post halon_skills_path, params: { name: "game_day", when: "x", tools: [], steps: "1." }
    assert_not Chat::CustomSkill.exists?(name: "game_day")
  end

  test "without the workflows flag the page does not exist" do
    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)

    get halon_skills_path

    assert_response :not_found
  end
end
