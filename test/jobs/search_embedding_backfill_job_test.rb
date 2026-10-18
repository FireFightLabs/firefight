require "test_helper"

class SearchEmbeddingBackfillJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "an incident with no vector is written through the same job as one that changed, and one with a vector is left" do
    embedded = incidents(:resolved_minor_ws1)
    SearchEmbedding.create!(workspace: embedded.workspace, embeddable: embedded, vector: Array.new(SearchEmbedding::DIMENSIONS, 0.1),
                            content_digest: "x", model: FirefightAi.embedding_model)

    SearchEmbeddingBackfillJob.perform_now

    assert_enqueued_with(job: WriteSearchEmbeddingJob, args: [ Incident.name, @incident.id ])
    refute written?(Incident.name, embedded.id)
  end

  test "only what a search would hold is written, so a draft postmortem and a rehearsal's finding are left" do
    draft = postmortems(:postmortem_resolved_ws1)
    rehearsal = finding_for(rehearsal: true)
    real = finding_for(rehearsal: false)
    clear_enqueued_jobs

    SearchEmbeddingBackfillJob.new.perform(SearchEmbeddingBackfillJob::TYPES.index(Investigation::Finding))
    SearchEmbeddingBackfillJob.new.perform(SearchEmbeddingBackfillJob::TYPES.index(Postmortem))

    assert written?(Investigation::Finding.name, real.id)
    refute written?(Investigation::Finding.name, rehearsal.id)
    refute written?(Postmortem.name, draft.id)
  end

  test "it goes a batch at a time and queues the next batch from where it stopped, so it can be started again" do
    SearchEmbeddingBackfillJob.new.perform(0)

    after = enqueued_jobs.find { |job| job["job_class"] == SearchEmbeddingBackfillJob.name }
    assert_equal [ 0, Incident.where.missing(:search_embedding).order(id: :desc).pick(:id) ], after["arguments"]
    assert_operator Time.iso8601(after["scheduled_at"]), :>, Time.current
  end

  test "an empty batch moves on to the next kind of record, and the last kind ends it" do
    last = SearchEmbeddingBackfillJob::TYPES.size - 1
    SearchEmbeddingBackfillJob.new.perform(0, "ffffffff-ffff-ffff-ffff-ffffffffffff")

    assert_enqueued_with(job: SearchEmbeddingBackfillJob, args: [ 1 ])

    clear_enqueued_jobs
    SearchEmbeddingBackfillJob.new.perform(last, "ffffffff-ffff-ffff-ffff-ffffffffffff")
    assert_no_enqueued_jobs
  end

  private

  def written?(type, id)
    enqueued_jobs.any? { |job| job["job_class"] == WriteSearchEmbeddingJob.name && job["arguments"] == [ type, id ] }
  end

  def finding_for(rehearsal:)
    investigation = @workspace.investigations.create!(
      subject: (@incident unless rehearsal), trigger_source: rehearsal ? Investigation::TRIGGER_REHEARSAL : Investigation::TRIGGER_COMMAND,
      rehearsal: rehearsal, brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }, max_turns: 10, max_spend_cents: 400
    )
    investigation.conclude!(summary: "The pool was too small")
  end
end
