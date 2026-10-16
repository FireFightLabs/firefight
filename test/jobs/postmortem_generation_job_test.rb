require "test_helper"

class PostmortemGenerationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:resolved_ws1),
      incident_severity: incident_severities(:minor_ws1),
      name: "Job test incident",
      is_private: false,
      channel_id: "C_JOB_TEST",
      resolved_at: 1.hour.ago,
      source: Incident::SOURCE_SLACK
    )
  end

  test "generates when the placeholder says a generation is running" do
    attempt = Postmortem.start_generation!(@incident, by: @member).generation_attempt
    PostmortemGenerationService.any_instance.expects(:generate!).with(@incident, generated_by: @member, attempt: attempt).once

    PostmortemGenerationJob.perform_now(@incident.id, attempt)
  end

  test "does nothing without a placeholder, so a stray job cannot overwrite a document" do
    FirefightAi::PostmortemGenerator.expects(:new).never

    PostmortemGenerationJob.perform_now(@incident.id)
  end

  test "skips when an already-filled postmortem exists" do
    incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @incident.incident_status,
      incident_severity: @incident.incident_severity,
      name: "Another incident",
      is_private: false,
      channel_id: "C_WITH_POSTMORTEM",
      resolved_at: 1.hour.ago,
      source: Incident::SOURCE_SLACK
    )
    Postmortem.create!(
      incident: incident,
      generated_by: @member,
      title: "Existing",
      status: Postmortem::STATUS_DRAFT,
      content: { "html" => "already filled" }
    )

    FirefightAi::PostmortemGenerator.expects(:new).never
    PostmortemGenerationJob.perform_now(incident.id)
  end

  test "a human setting status to in_progress is not mistaken for a running generation" do
    Postmortem.create!(
      incident: @incident, generated_by: @member, title: "Being written by hand",
      status: Postmortem::STATUS_IN_PROGRESS, content: { "html" => "<p>draft</p>" }
    )
    FirefightAi::PostmortemGenerator.expects(:new).never

    PostmortemGenerationJob.perform_now(@incident.id)

    assert_equal "<p>draft</p>", @incident.reload.postmortem.content["html"]
  end

  test "an entitlement block marks the placeholder failed with a readable reason" do
    Postmortem.start_generation!(@incident, by: @member)
    Entitlements.stubs(:allows?).with(@workspace, Entitlements::AI).returns(false)
    FirefightAi::PostmortemGenerator.expects(:new).never

    PostmortemGenerationJob.perform_now(@incident.id)

    postmortem = @incident.reload.postmortem
    assert postmortem.generation_failed?
    assert_equal "EntitlementBlocked", postmortem.generation_error
  end

  test "a terminal AI failure keeps the placeholder, marked failed with the reason, and it can be retried" do
    Postmortem.start_generation!(@incident, by: @member)
    generator = mock("generator")
    generator.stubs(:generate).raises(FirefightAi::TerminalError.new("too long", reason: "ContextLengthExceededError"))
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)
    WorkspaceAdapter.stubs(:for).returns(stub(post_postmortem_generation_failed: nil))

    PostmortemGenerationJob.perform_now(@incident.id)

    postmortem = @incident.reload.postmortem
    assert postmortem.generation_failed?
    assert_equal "ContextLengthExceededError", postmortem.generation_error
    assert_equal Postmortem::STATUS_DRAFT, postmortem.status

    assert Postmortem.start_generation!(@incident, by: @member), "a failed generation can be started again"
    assert postmortem.reload.generating?
  end

  test "a generation that outlives the stale timeout and a retry is dropped when it finishes, and the retry's draft stands" do
    WorkspaceAdapter.stubs(:for).returns(stub(post_postmortem_message: { message_id: "1.2" }, pin_message: nil, post_postmortem_generation_failed: nil))
    service = PostmortemGenerationService.new(@workspace)
    service.start!(@incident, by: @member)
    first_job = generation_job_arguments
    # The first job is still writing when it goes stale, the sweep gives it up, and a retry runs to the end.
    newer = draft("Newer draft")
    older = draft("Older draft")
    first_call = true
    retry_meanwhile = lambda do
      travel Postmortem::GENERATION_STALE_AFTER + 1.minute
      PostmortemGenerationJob.give_up_interrupted!(Postmortem.generation_stalled.find_by!(incident: @incident))
      service.start!(@incident, by: @member)
      PostmortemGenerationJob.perform_now(*generation_job_arguments)
    end
    generator = Object.new
    generator.define_singleton_method(:generate) do |_incident|
      next newer unless first_call

      first_call = false
      retry_meanwhile.call
      older
    end
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)

    PostmortemGenerationJob.perform_now(*first_job)

    postmortem = @incident.reload.postmortem
    assert_equal "Newer draft", postmortem.title
    assert_nil postmortem.generation_state
    assert_equal 1, @incident.incident_events.where(event_type: IncidentEvent::POSTMORTEM_GENERATED).count
  end

  test "a job for an attempt a retry replaced neither generates nor fails the retry" do
    old_attempt = Postmortem.start_generation!(@incident, by: @member).generation_attempt
    @incident.reload.postmortem.give_up_generation!
    Postmortem.start_generation!(@incident, by: @member)
    FirefightAi::PostmortemGenerator.expects(:new).never

    PostmortemGenerationJob.perform_now(@incident.id, old_attempt)
    assert_not PostmortemGenerationJob.new(@incident.id, old_attempt).record_failure(ActiveRecord::RecordInvalid.new)
    PostmortemGenerationJob.interrupted_too_often(@incident.id, old_attempt)

    assert @incident.reload.postmortem.generating?
  end

  test "two starts while one is running yield one job" do
    assert Postmortem.start_generation!(@incident, by: @member)
    assert_nil Postmortem.start_generation!(@incident, by: @member)
  end

  test "blocked entitlement runs no generation and marks the placeholder failed" do
    deny_entitlements!
    Postmortem.start_generation!(@incident, by: @member)
    FirefightAi::PostmortemGenerator.expects(:new).never

    PostmortemGenerationJob.perform_now(@incident.id)

    assert @incident.reload.postmortem.generation_failed?
  end

  test "discards on record not found" do
    FirefightAi::PostmortemGenerator.expects(:new).never
    assert_nothing_raised do
      PostmortemGenerationJob.perform_now(SecureRandom.uuid)
    end
  end

  test "discards terminal AI errors without retry and notifies the requester" do
    Postmortem.start_generation!(@incident, by: @member)
    generator = mock("generator")
    generator.stubs(:generate).raises(FirefightAi::TerminalError.new("too long", reason: "ContextLengthExceededError"))
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)

    adapter = mock("adapter")
    WorkspaceAdapter.stubs(:for).returns(adapter)
    adapter.expects(:post_postmortem_generation_failed)
      .with(has_entries(incident: @incident, reason: "ContextLengthExceededError", retrying: false)).once

    assert_nothing_raised do
      PostmortemGenerationJob.perform_now(@incident.id)
    end
  end

  test "an AI account out of credit fails the generation once, and the requester and the page are told why in plain words" do
    Postmortem.start_generation!(@incident, by: @member)
    generator = mock("generator")
    generator.stubs(:generate).raises(FirefightAi::OutOfCredit.new("OpenRouter: can only afford 900"))
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)
    said = "Halon couldn't reach its AI just now."
    adapter = mock("adapter")
    WorkspaceAdapter.stubs(:for).returns(adapter)
    adapter.expects(:post_postmortem_generation_failed).with(has_entries(incident: @incident, retrying: false, note: said)).once

    assert_nothing_raised { PostmortemGenerationJob.perform_now(@incident.id) }

    postmortem = @incident.reload.postmortem
    assert postmortem.generation_failed?
    assert_equal AiCredit::REASON, postmortem.generation_error
    assert_equal said, postmortem.generation_failure_note
  end

  test "an error the engine did not classify marks the placeholder failed instead of leaving it generating" do
    Postmortem.start_generation!(@incident, by: @member)
    PostmortemGenerationService.any_instance.stubs(:generate!).raises(ActiveRecord::RecordInvalid)
    adapter = mock("adapter")
    WorkspaceAdapter.stubs(:for).returns(adapter)
    adapter.expects(:post_postmortem_generation_failed).with(has_entries(reason: "RecordInvalid", retrying: false)).once

    assert_raises(ActiveRecord::RecordInvalid) do
      PostmortemGenerationJob.perform_now(@incident.id)
    end

    postmortem = @incident.reload.postmortem
    assert postmortem.generation_failed?
    assert_equal "RecordInvalid", postmortem.generation_error
  end

  private

  def generation_job_arguments
    enqueued_jobs.select { |job| job[:job] == PostmortemGenerationJob }.last.fetch(:args).then { |args| ActiveJob::Arguments.deserialize(args) }
  end

  def draft(title)
    FirefightAi::PostmortemGenerator::Draft.new(title: title, summary: nil, sections: {}, model: "gpt-4o")
  end
end
