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

  test "a workspace without AI is passed over before anything is queued for it" do
    other = incidents(:active_p0_ws2)
    Entitlements.stubs(:allows?).returns(true)
    Entitlements.stubs(:allows?).with(other.workspace, Entitlements::AI).returns(false)

    SearchEmbeddingBackfillJob.new.perform(0)

    assert written?(Incident.name, @incident.id)
    refute written?(Incident.name, other.id)
  end

  test "only one backfill runs at a time, however often it is started" do
    assert_equal 1, SearchEmbeddingBackfillJob.concurrency_limit
    assert_equal SearchEmbeddingBackfillJob::CONCURRENCY_KEY, SearchEmbeddingBackfillJob.new.concurrency_key.split("/").last
  end

  test "a vector another writer saved first from the current words is kept rather than failing the job" do
    stub_embed
    assert_nil @incident.search_embedding
    winner = SearchEmbedding.create!(workspace: @workspace, embeddable: @incident, vector: vector(0.2), model: FirefightAi.embedding_model,
                                     content_digest: SearchEmbedding.digest_for(@incident.search_text.to_s.squish))

    assert_equal winner, SearchEmbeddingService.new(@workspace).write!(@incident)
    assert_equal 1, SearchEmbedding.where(embeddable: @incident).count
  end

  test "a vector another writer saved first from older words is written again from the current ones" do
    stub_embed
    assert_nil @incident.search_embedding
    stale = SearchEmbedding.create!(workspace: @workspace, embeddable: @incident, vector: vector(0.2), model: FirefightAi.embedding_model, content_digest: "older")

    written = SearchEmbeddingService.new(@workspace).write!(@incident)

    assert_equal stale, written
    assert_equal SearchEmbedding.digest_for(@incident.search_text.to_s.squish), stale.reload.content_digest
  end

  test "two writes of one record wait for each other, so the second finds the first's vector instead of paying again" do
    assert_equal "#{Incident.name}:#{@incident.id}", WriteSearchEmbeddingJob.new(Incident.name, @incident.id).concurrency_key.split("/").last
  end

  private

  def vector(value) = Array.new(SearchEmbedding::DIMENSIONS, value)

  def stub_embed
    FirefightAi.stubs(:embed).returns(Struct.new(:vectors, :model).new(vector(0.1), FirefightAi.embedding_model))
  end

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
