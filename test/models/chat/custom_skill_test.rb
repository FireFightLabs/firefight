require "test_helper"

class Chat::CustomSkillTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
  end

  def content(steps: "1. Declare it with `declare_incident`.", tools: [ "declare_incident" ], used_when: "Someone asks to open a game day")
    { "when" => used_when, "tools" => tools, "steps" => steps }
  end

  def make(name = "game_day", **options)
    Chat::CustomSkill.create_with!(workspace: @workspace, name: name, content: content(**options), by: @alice)
  end

  test "a new skill has its first version live, written by the person" do
    skill = make("Game-Day")

    assert_equal "game_day", skill.name
    version = skill.live_version
    assert_equal [ 1, Chat::CustomSkill::Version::STATUS_LIVE, Chat::CustomSkill::Version::AUTHOR_PERSON, @alice ],
                 [ version.number, version.status, version.author_kind, version.author ]
    assert_equal [ "declare_incident" ], version.tools
  end

  test "a skill switched off is not loaded, says so to a workflow that runs it, and a copy switched off gives Firefight's back" do
    skill = make
    skill.switch!(on: false)

    assert_not skill.reload.enabled?
    assert_not_includes Chat::Skill.available_to(@workspace).map(&:name), "game_day"
    assert_equal "game_day is switched off on the Skills page.", Chat::CustomSkill.off_reason(@workspace, "game_day")

    copy = Chat::CustomSkill.copy!(Chat::Skill.find("declaring"), workspace: @workspace, by: @alice)
    copy.switch!(on: false)
    used = Chat::Skill.available_to(@workspace).select { |each| each.name == "declaring" }
    assert_equal [ nil ], used.map(&:custom_skill_id), "Firefight's own is used while the copy is off"
    assert_nil Chat::CustomSkill.off_reason(@workspace, "declaring"), "a copy that is off leaves Firefight's skill to run"

    skill.switch!(on: true)
    assert_includes Chat::Skill.available_to(@workspace).map(&:name), "game_day"
  end

  test "names must be the workspace's own and not one of Firefight's" do
    make
    assert_raises(ActiveRecord::RecordInvalid) { make }

    error = assert_raises(ActiveRecord::RecordInvalid) { make("declaring") }
    assert_match "is the name of one of Firefight's skills", error.message

    assert_not Chat::CustomSkill.new(workspace: @workspace, name: "9 lives").valid?
  end

  test "a skill holds no secret" do
    error = assert_raises(ActiveRecord::RecordInvalid) { make(steps: "Use token ghp_#{'a' * 36} to call GitHub.") }
    assert_match "looks like it holds a secret", error.message
  end

  test "saving writes a new live version on the one the person saw, and refuses one someone replaced" do
    skill = make
    first = skill.live_version
    stale = Chat::CustomSkill.find(skill.id)

    second = skill.write!(content(steps: "1. Ask first, then `declare_incident`."), by: @bob, reason: "Ask first.")

    assert_equal [ 2, @bob, first.id ], [ second.number, second.author, second.parent_version_id ]
    assert_equal Chat::CustomSkill::Version::STATUS_RETIRED, first.reload.status
    error = assert_raises(Chat::CustomSkill::Writing::Refused) { stale.write!(content, by: @alice) }
    assert_equal Chat::CustomSkill::Writing::CHANGED_FIRST, error.message
    assert_equal second, skill.reload.live_version
  end

  test "a version never changes once written, and an older one is restored as a new version" do
    skill = make
    first = skill.live_version
    skill.write!(content(steps: "1. Something else with `declare_incident`."), by: @bob)

    assert_not first.update(steps: "Changed")
    restored = skill.reload.restore!(first.reload, by: @alice)

    assert_equal [ 3, first.steps, "Restored version 1." ], [ restored.number, restored.steps, restored.reason ]
  end

  test "Halon's proposal waits on a person and goes live once accepted" do
    skill = make
    proposal = Chat::CustomSkill.propose_for!(@workspace, name: "game_day", content: content(steps: "1. Page first, then `declare_incident`."),
                                                           reason: "The team pages before declaring.")

    assert proposal.proposed?
    assert_equal 1, skill.reload.live_version.number
    assert_nil skill.accept_blocked_reason(proposal)

    skill.accept!(proposal, by: @bob)

    assert_equal [ proposal, @bob ], [ skill.reload.live_version, proposal.reload.decided_by ]
    assert proposal.live?
  end

  test "a proposal someone overtook cannot be accepted as written, though it can be edited first" do
    skill = make
    proposal = skill.propose!(content(steps: "1. Halon's way with `declare_incident`."), reason: "Seen in a chat.")
    skill.write!(content(steps: "1. Bob's way with `declare_incident`."), by: @bob)

    assert_match "changed since Halon proposed this", skill.accept_blocked_reason(proposal)
    assert_raises(Chat::CustomSkill::Writing::Refused) { skill.accept!(proposal, by: @alice) }

    skill.accept!(proposal, by: @alice, content: content(steps: "1. Both ways with `declare_incident`."))

    assert_equal "1. Both ways with `declare_incident`.", skill.reload.live_version.steps

    other = skill.propose!(content, reason: "Again.")
    error = assert_raises(Chat::CustomSkill::Writing::Refused) { skill.accept!(other, by: @alice, content: content, name: "renamed") }
    assert_equal Chat::CustomSkill::Writing::KEEPS_NAME, error.message
    assert_equal Chat::CustomSkill::Version::STATUS_EDITED, proposal.reload.status
  end

  test "a new skill Halon proposed stays out of sight when dismissed and gives its name back" do
    proposal = Chat::CustomSkill.propose_for!(@workspace, name: "rotate_keys", content: content, reason: "Asked twice this week.")
    skill = proposal.custom_skill
    assert_not_includes Chat::Skill.available_to(@workspace).map(&:name), "rotate_keys"

    skill.dismiss!(proposal, by: @alice)

    assert skill.dormant?
    assert_equal "Alice Example dismissed your proposed skill rotate_keys, so it is unchanged.",
                 proposal.reload.outcome_note.sub(@alice.actor_display_name, "Alice Example")
    assert make("rotate_keys").live_version
  end

  test "Halon is told each decision once" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    proposal = Chat::CustomSkill.propose_for!(@workspace, name: "rotate_keys", content: content, reason: "Asked twice.", conversation: conversation)
    proposal.custom_skill.accept!(proposal, by: @bob)

    assert_equal [ proposal ], Chat::CustomSkill::Version.untold_for!(conversation)
    assert_empty Chat::CustomSkill::Version.untold_for!(conversation)
  end

  test "a copy keeps the library skill's name, is used in its place and hears of a newer version" do
    library = Chat::Skill.find("declaring")
    copy = Chat::CustomSkill.copy!(library, workspace: @workspace, by: @alice)

    assert copy.copy?
    assert_equal [ "declaring", Chat::Skill::SOURCE_FIREFIGHT, library.version, library.content ],
                 [ copy.name, copy.source, copy.library_version, copy.library_base ]
    assert_equal Chat::CustomSkill::Version::AUTHOR_FIREFIGHT, copy.live_version.author_kind
    used = Chat::Skill.available_to(@workspace).select { |skill| skill.name == "declaring" }
    assert_equal [ copy.id ], used.map(&:custom_skill_id)
    assert_nil copy.library_update

    newer = library.with(version: library.version + 1, steps: "#{library.steps}\n9. Say it is declared.")
    Chat::Skill.stubs(:find).with("declaring").returns(newer)
    assert_equal newer, copy.library_update
    assert_equal library.steps, copy.reload.live_version.steps, "a copy is never changed under the workspace"

    copy.keep_own!
    assert_nil copy.library_update

    copy.update!(library_dismissed_version: nil)
    copy.take_library!(by: @bob)
    assert_equal [ newer.steps, newer.version, @bob ], [ copy.reload.live_version.steps, copy.library_version, copy.live_version.author ]
  end

  test "a skill a workflow runs cannot be deleted or renamed, while a copy can be deleted since Firefight's own takes over" do
    skill = make
    workflow = Workflow.create!(workspace: @workspace, name: "Game day")
    workflow.open_draft!(by: @alice).update_columns(steps: [ { "id" => "step_1", "name" => "drill", "kind" => "run_skill", "config" => { "skill" => "game_day" } } ])

    counted = Chat::CustomSkill.where(id: skill.id).with_usage_counts.first
    assert_equal 1, counted.usage_count
    assert_equal [ workflow ], skill.workflows_using.to_a
    assert_match "take it out of that workflow", counted.deletion_blocked_reason
    assert_match "keeps it", counted.rename_blocked_reason
    error = assert_raises(Chat::CustomSkill::Writing::Refused) { skill.write!(skill.live_version.content, by: @alice, name: "drill") }
    assert_match "keeps it", error.message

    copy = Chat::CustomSkill.copy!(Chat::Skill.find("declaring"), workspace: @workspace, by: @alice)
    Workflow.create!(workspace: @workspace, name: "Declare").open_draft!(by: @alice)
            .update_columns(steps: [ { "id" => "step_1", "name" => "declare", "kind" => "for_each", "config" => { "steps" => [ { "config" => { "skill" => "declaring" } } ] } } ])
    assert_equal 1, copy.usage_count
    assert_nil copy.deletion_blocked_reason
  end

  test "a SKILL.md file reads back as the skill it was written from" do
    definition = make.definition

    parsed = Chat::CustomSkill::Document.parse(Chat::CustomSkill::Document.render(definition))

    assert_equal "game_day", parsed.name
    assert_equal definition.content.slice("when", "tools", "steps"), parsed.content.slice("when", "tools", "steps")
  end

  test "a SKILL.md from another agent reads its description and allowed tools" do
    parsed = Chat::CustomSkill::Document.parse("---\nname: pdf-tidy\ndescription: Tidies PDFs\nallowed-tools: declare_incident resolve_incident\n---\nDo it.\n")

    assert_equal [ "pdf-tidy", "Tidies PDFs", %w[declare_incident resolve_incident], "Do it." ],
                 [ parsed.name, parsed.content["when"], parsed.content["tools"], parsed.content["steps"] ]
    assert_raises(Chat::CustomSkill::Document::Unreadable) { Chat::CustomSkill::Document.parse("no front matter") }
    assert_raises(Chat::CustomSkill::Document::Unreadable) { Chat::CustomSkill::Document.parse("---\nwhen: x\n---\nsteps") }
  end

  test "Halon loads the workspace's live skills beside Firefight's" do
    skill = make
    names = Chat::Skill.available_to(@workspace).map(&:name)
    assert_includes names, "game_day"
    assert_includes names, "declaring"

    found = Chat::Skill.available_to(@workspace).find { |each| each.name == "game_day" }
    assert_equal [ Chat::Skill::SOURCE_WORKSPACE, skill.id, 1 ], [ found.source, found.custom_skill_id, found.version ]
  end
end
