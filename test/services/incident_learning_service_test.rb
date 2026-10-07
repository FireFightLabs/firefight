require "test_helper"

class IncidentLearningServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @entry = catalog_entries(:auth_service)
    IncidentFieldValue.create!(incident: @incident, incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: @entry)
    Entitlements.stubs(:allows?).returns(true)
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)
    @adapter = @workspace.adapter
    Workspace.any_instance.stubs(:adapter).returns(@adapter)
  end

  test "at resolve the lessons are saved unconfirmed, about what they name, and the channel is asked to confirm them" do
    stub_lessons([ lesson("Auth Service keeps sessions in Redis", about: @entry.name) ])
    @adapter.expects(:post_learned_memories).with { |channel_id:, thread_id:, post:|
      channel_id == @incident.channel_id && thread_id.nil? && post.kind == Chat::MemoryPost::KIND_INCIDENT &&
        post.incident_identifier == @incident.identifier && post.memories.map(&:text) == [ "Auth Service keeps sessions in Redis" ]
    }.returns(message_id: "1.1", channel_id: @incident.channel_id)

    saved = IncidentLearningService.new(@workspace).learn!(@incident)

    memory = saved.sole
    assert_equal Chat::Memory::STATE_UNCONFIRMED, memory.state
    assert_equal @entry, memory.subject
    assert_equal @incident, memory.source
    post = Chat::MemoryPost.find_by!(incident: @incident)
    assert_equal [ memory.id ], post.memory_ids
    assert_equal "1.1", post.message_id
  end

  test "the extractor is handed what the workspace already holds on what the incident touches, rejected ones marked, never the incident's own" do
    own = Chat::Memory.create!(workspace: @workspace, text: "Sessions live in Redis", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    Chat::Memory.create!(workspace: @workspace, text: "Auth Service runs two instances", subject: @entry, state: Chat::Memory::STATE_CONFIRMED)
    Chat::Memory.create!(workspace: @workspace, text: "Auth Service uses MySQL", subject: @entry, state: Chat::Memory::STATE_REJECTED)
    Chat::Memory.create!(workspace: @workspace, text: "Deploys go out from main", state: Chat::Memory::STATE_UNCONFIRMED)
    Chat::Memory.create!(workspace: @workspace, text: "Platform pages at night", subject: catalog_entries(:platform_team), state: Chat::Memory::STATE_CONFIRMED)
    seen = nil
    FirefightAi::LessonExtractor.any_instance.stubs(:extract).with { |_incident, remembered:, **| (seen = remembered) || true }
                                .returns(FirefightAi::LessonExtractor::Result.new(lessons: [], verdicts: []))

    IncidentLearningService.new(@workspace).learn!(@incident)

    assert_equal [ [ "Auth Service runs two instances", false ], [ "Auth Service uses MySQL", true ], [ "Deploys go out from main", false ] ].sort,
                 seen.map { |each| [ each.text, each.rejected ] }.sort
    assert_not_includes seen.map(&:text), own.text
  end

  test "an incident that taught nothing posts nothing, and a workspace whose plan does not include AI learns nothing" do
    stub_lessons([])
    @adapter.expects(:post_learned_memories).never
    assert_empty IncidentLearningService.new(@workspace).learn!(@incident)

    Entitlements.stubs(:allows?).returns(false)
    FirefightAi::LessonExtractor.any_instance.expects(:extract).never
    assert_empty IncidentLearningService.new(@workspace).learn!(@incident)
  end

  test "a lesson a person rejected on an earlier incident is not learned again, and one already known is not saved twice" do
    earlier = incidents(:resolved_minor_ws1)
    Chat::Memory.create!(workspace: @workspace, text: "Auth Service keeps sessions in Redis", subject: @entry, state: Chat::Memory::STATE_REJECTED, source: earlier)
    Chat::Memory.create!(workspace: @workspace, text: "Deploys go out from main", state: Chat::Memory::STATE_CONFIRMED, source: earlier)
    stub_lessons([ lesson("auth service keeps sessions in redis", about: @entry.name), lesson("Deploys go out from main") ])
    @adapter.expects(:post_learned_memories).never

    assert_empty IncidentLearningService.new(@workspace).learn!(@incident)
    assert_not Chat::Memory.exists?(workspace: @workspace, source: @incident)
  end

  test "a completed postmortem confirms and corrects as whoever marked it completed, never the draft's author" do
    author = workspace_memberships(:alice_workspace_one)
    completer = workspace_memberships(:bob_workspace_one)
    right = Chat::Memory.create!(workspace: @workspace, text: "Sessions live in Redis", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    wrong = Chat::Memory.create!(workspace: @workspace, text: "The cause was DNS", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    stub_verdicts(agrees: right, contradicts: wrong, correction: "The cause was the connection pool")
    @adapter.expects(:post_learned_memories).never
    postmortem = completed_postmortem(author: author, completer: completer)

    IncidentLearningService.new(@workspace).learn!(@incident, postmortem: postmortem)

    assert_equal [ Chat::Memory::STATE_CONFIRMED, completer, postmortem ], right.reload.values_at(:state, :confirmed_by, :decided_by_postmortem)
    assert_equal [ Chat::Memory::STATE_REJECTED, completer ], wrong.reload.values_at(:state, :rejected_by)
    assert_equal [ "The cause was the connection pool", completer ], [ wrong.replaced_by.text, wrong.replaced_by.confirmed_by ]
  end

  test "a postmortem completed by a key confirms as a postmortem, and Halon never reads a person in it" do
    right = Chat::Memory.create!(workspace: @workspace, text: "Sessions live in Redis", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    stub_verdicts(agrees: right)
    postmortem = completed_postmortem(author: workspace_memberships(:alice_workspace_one), completer: api_keys(:full_access_key))

    IncidentLearningService.new(@workspace).learn!(@incident, postmortem: postmortem)

    right.reload
    assert_nil right.confirmed_by
    assert_includes right.line, "confirmed by a postmortem"
  end

  test "a postmortem never overrules a person: what a person confirmed is disputed with the reason, and a disputed one is never confirmed" do
    vouched = Chat::Memory.create!(workspace: @workspace, text: "The cause was DNS", state: Chat::Memory::STATE_CONFIRMED, source: @incident,
                                   confirmed_by: workspace_memberships(:alice_workspace_one))
    disputed = Chat::Memory.create!(workspace: @workspace, text: "Sessions live in Redis", state: Chat::Memory::STATE_DISPUTED, source: @incident)
    verdict = FirefightAi::LessonExtractor::Verdict
    FirefightAi::LessonExtractor.any_instance.stubs(:extract).returns(FirefightAi::LessonExtractor::Result.new(lessons: [], verdicts: [
      verdict.new(memory_id: vouched.id, verdict: FirefightAi::Schemas::Lessons::CONTRADICTS, correction: "The cause was the connection pool")
    ]))
    postmortem = completed_postmortem(author: workspace_memberships(:alice_workspace_one), completer: workspace_memberships(:bob_workspace_one))

    IncidentLearningService.new(@workspace).learn!(@incident, postmortem: postmortem)

    assert_equal Chat::Memory::STATE_DISPUTED, vouched.reload.state
    assert_equal "The #{@incident.identifier} postmortem says otherwise and gives this instead. The cause was the connection pool", vouched.state_reason
    assert_nil vouched.replaced_by
    assert_not disputed.reload.confirm_from_postmortem!(postmortem, by: nil)
    assert_equal Chat::Memory::STATE_DISPUTED, disputed.state
  end

  test "new lessons from a postmortem are posted in the channel under their own title" do
    stub_lessons([ lesson("The pool is shared by checkout and billing") ])
    @adapter.expects(:post_learned_memories).with { |post:, **| post.kind == Chat::MemoryPost::KIND_POSTMORTEM }.returns(message_id: "1.2", channel_id: @incident.channel_id)

    saved = IncidentLearningService.new(@workspace).learn!(@incident, postmortem: completed_postmortem(author: workspace_memberships(:alice_workspace_one),
                                                                                                       completer: workspace_memberships(:bob_workspace_one)))

    assert_equal [ "The pool is shared by checkout and billing" ], saved.map(&:text)
  end

  test "an answer marked wrong, and a fix that was undone, reach the lessons as mistakes, never as facts" do
    run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
                                            status: Investigation::STATUS_SUCCEEDED)
    finding = run.create_finding!(summary: "The deploy at 14:02 did it", outcome: Investigation::Finding::OUTCOME_WRONG)
    fix = Investigation::RemediationPlan.create!(finding: finding, summary: "Roll the deploy back", status: Investigation::RemediationPlan::STATUS_APPLIED)
    Investigation::RemediationPlan.create!(finding: finding, undoes: fix, summary: "Redeploy", status: Investigation::RemediationPlan::STATUS_APPLIED)
    seen = nil
    FirefightAi::LessonExtractor.any_instance.stubs(:extract).with { |_incident, sources:, **| (seen = sources) || true }
                                .returns(FirefightAi::LessonExtractor::Result.new(lessons: [], verdicts: []))

    IncidentLearningService.new(@workspace).learn!(@incident)

    texts = seen.to_h { |source| [ source.title, source.text ] }
    assert_not_includes texts["What the investigation found"], "The deploy at 14:02 did it"
    assert_includes texts["What Halon got wrong"], "Halon's answer, which the team marked wrong: The deploy at 14:02 did it"
    assert_includes texts["What Halon got wrong"], "The fix Halon proposed (Roll the deploy back) was applied and then undone"
  end

  test "an answer marked wrong after its incident ended learns again, and one marked while it runs waits for the end" do
    run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
                                            status: Investigation::STATUS_SUCCEEDED)
    finding = run.create_finding!(summary: "The deploy did it")
    member = workspace_memberships(:alice_workspace_one)

    assert_no_enqueued_jobs(only: IncidentMistakeLearningJob) { finding.record_verdict!(Investigation::Finding::OUTCOME_WRONG, by: member) }

    Incident.any_instance.stubs(:closed?).returns(true)
    finding.record_verdict!(Investigation::Finding::OUTCOME_CONFIRMED, by: member)
    assert_enqueued_with(job: IncidentMistakeLearningJob, args: [ @incident.id ]) { finding.record_verdict!(Investigation::Finding::OUTCOME_WRONG, by: member) }
    finding.record_verdict!(Investigation::Finding::OUTCOME_CONFIRMED, by: member)
    assert_no_enqueued_jobs(only: IncidentMistakeLearningJob) { finding.record_verdict!(Investigation::Finding::OUTCOME_WRONG, by: member) }
  end

  test "a late mistake asks only for its lesson, against every lesson the incident has, and an archived channel only keeps it" do
    rejected = Chat::Memory.learn!(@workspace, text: "Deploys break checkout", subject: nil, source: @incident).memory
    rejected.reject!(by: workspace_memberships(:alice_workspace_one), reason: "No")
    FirefightAi::LessonExtractor.any_instance.expects(:extract).with { |_incident, only_mistakes:, known:, **| only_mistakes && known.map(&:id).include?(rejected.id) }
                                .returns(FirefightAi::LessonExtractor::Result.new(lessons: [ lesson("A 5xx after a deploy has meant a full disk") ], verdicts: []))
    @adapter.stubs(:post_learned_memories).raises(AdapterError::IsArchived)

    saved = IncidentLearningService.new(@workspace).learn_from_mistake!(@incident)

    assert_equal [ "A 5xx after a deploy has meant a full disk" ], saved.map(&:text)
    assert_not Chat::MemoryPost.exists?(incident: @incident), "a message that could not be posted is not kept"
  end

  private

  def lesson(fact, about: nil) = FirefightAi::LessonExtractor::Lesson.new(fact: fact, about: about, confidence: 0.9)

  def stub_verdicts(agrees:, contradicts: nil, correction: nil)
    verdict = FirefightAi::LessonExtractor::Verdict
    FirefightAi::LessonExtractor.any_instance.stubs(:extract).returns(FirefightAi::LessonExtractor::Result.new(lessons: [], verdicts: [
      verdict.new(memory_id: agrees.id, verdict: FirefightAi::Schemas::Lessons::AGREES, correction: nil),
      (verdict.new(memory_id: contradicts.id, verdict: FirefightAi::Schemas::Lessons::CONTRADICTS, correction: correction) if contradicts)
    ].compact))
  end

  def completed_postmortem(author:, completer:)
    postmortem = Postmortem.create!(incident: @incident, generated_by: author, title: "Pool", status: Postmortem::STATUS_IN_REVIEW,
                                    content: { "html" => "<p>It was the pool</p>" })
    postmortem.update_status!(Postmortem::STATUS_COMPLETED, by: completer)
    postmortem
  end

  def stub_lessons(lessons)
    FirefightAi::LessonExtractor.any_instance.stubs(:extract).returns(FirefightAi::LessonExtractor::Result.new(lessons: lessons, verdicts: []))
  end
end
