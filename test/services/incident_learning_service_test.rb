require "test_helper"

class IncidentLearningServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @entry = catalog_entries(:auth_service)
    IncidentFieldValue.create!(incident: @incident, incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: @entry)
    FeatureFlags.stubs(:enabled?).returns(true)
    Entitlements.stubs(:allows?).returns(true)
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)
    @adapter = @workspace.adapter
    Workspace.any_instance.stubs(:adapter).returns(@adapter)
  end

  test "at resolve the lessons are saved unconfirmed, about what they name, and the channel is asked to confirm them" do
    stub_lessons([ lesson("Auth Service keeps sessions in Redis", about: @entry.name) ])
    @adapter.expects(:post_learned_memories).with { |channel_id:, incident_id:, incident_identifier:, memories:|
      channel_id == @incident.channel_id && incident_id == @incident.id && memories.map(&:text) == [ "Auth Service keeps sessions in Redis" ]
    }.returns(message_id: "1.1", channel_id: @incident.channel_id)

    saved = IncidentLearningService.new(@workspace).learn!(@incident)

    memory = saved.sole
    assert_equal Chat::Memory::STATE_UNCONFIRMED, memory.state
    assert_equal @entry, memory.subject
    assert_equal @incident, memory.source
  end

  test "an incident that taught nothing posts nothing, and a workspace without the agent learns nothing" do
    stub_lessons([])
    @adapter.expects(:post_learned_memories).never
    assert_empty IncidentLearningService.new(@workspace).learn!(@incident)

    FeatureFlags.stubs(:enabled?).returns(false)
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

  test "a completed postmortem confirms what it agrees with and corrects what it contradicts, without posting" do
    right = Chat::Memory.create!(workspace: @workspace, text: "Sessions live in Redis", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    wrong = Chat::Memory.create!(workspace: @workspace, text: "The cause was DNS", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    verdict = FirefightAi::LessonExtractor::Verdict
    FirefightAi::LessonExtractor.any_instance.stubs(:extract).returns(FirefightAi::LessonExtractor::Result.new(lessons: [], verdicts: [
      verdict.new(memory_id: right.id, verdict: FirefightAi::Schemas::Lessons::AGREES, correction: nil),
      verdict.new(memory_id: wrong.id, verdict: FirefightAi::Schemas::Lessons::CONTRADICTS, correction: "The cause was the connection pool")
    ]))
    @adapter.expects(:post_learned_memories).never
    postmortem = Postmortem.create!(incident: @incident, generated_by: workspace_memberships(:alice_workspace_one), title: "Pool",
                                    status: Postmortem::STATUS_COMPLETED, content: { "html" => "<p>It was the pool</p>" })

    IncidentLearningService.new(@workspace).learn!(@incident, postmortem: postmortem)

    assert_equal Chat::Memory::STATE_CONFIRMED, right.reload.state
    assert_equal workspace_memberships(:alice_workspace_one), right.confirmed_by
    assert_equal Chat::Memory::STATE_REJECTED, wrong.reload.state
    assert_equal "The cause was the connection pool", wrong.replaced_by.text
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
  end

  private

  def lesson(fact, about: nil) = FirefightAi::LessonExtractor::Lesson.new(fact: fact, about: about, confidence: 0.9)

  def stub_lessons(lessons)
    FirefightAi::LessonExtractor.any_instance.stubs(:extract).returns(FirefightAi::LessonExtractor::Result.new(lessons: lessons, verdicts: []))
  end
end
