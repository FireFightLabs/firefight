require "test_helper"

class IncidentLearningServiceTest < ActiveSupport::TestCase
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

  private

  def lesson(fact, about: nil) = FirefightAi::LessonExtractor::Lesson.new(fact: fact, about: about, confidence: 0.9)

  def stub_lessons(lessons)
    FirefightAi::LessonExtractor.any_instance.stubs(:extract).returns(FirefightAi::LessonExtractor::Result.new(lessons: lessons, verdicts: []))
  end
end
