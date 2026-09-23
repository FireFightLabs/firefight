require "test_helper"

class SearchEmbeddingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    Entitlements.stubs(:allows?).returns(true)
  end

  test "an incident is written down as what people said about it, not as its machinery" do
    text = @incident.search_text

    assert_match @incident.identifier, text
    assert_match @incident.name, text
    assert_match @incident.incident_severity.name, text
  end

  test "embedding a record once is enough until its words change" do
    stub_embedding

    SearchEmbeddingService.new(@workspace).write!(@incident)
    first = @incident.reload.search_embedding

    FirefightAi.expects(:embed).never
    SearchEmbeddingService.new(@workspace).write!(@incident)

    assert_equal first.updated_at, @incident.reload.search_embedding.updated_at
  end

  test "changed words are embedded again" do
    stub_embedding
    SearchEmbeddingService.new(@workspace).write!(@incident)
    digest = @incident.reload.search_embedding.content_digest

    @incident.update!(summary: "Checkout is failing for EU customers only")
    SearchEmbeddingService.new(@workspace).write!(@incident)

    assert_not_equal digest, @incident.reload.search_embedding.content_digest
  end

  test "the closest match to a question comes back first, with what it needs to judge it" do
    other = incidents(:resolved_minor_ws1)
    stub_embedding(vectors: { @incident.search_text => near, other.search_text => far, "Checkout is broken" => near })
    SearchEmbeddingService.new(@workspace).write!(@incident)
    SearchEmbeddingService.new(@workspace).write!(other)

    matches = SearchEmbeddingService.new(@workspace).similar_to("Checkout is broken")

    assert_equal @incident, matches.first.record
    assert_equal "incident", matches.first.kind
    assert_equal @incident.identifier, matches.first.facts[:identifier]
    assert matches.first.similarity > matches.last.similarity
  end

  test "another workspace's incidents are never a match" do
    stub_embedding
    other = incidents(:active_p0_ws2)
    SearchEmbeddingService.new(other.workspace).write!(other)

    matches = SearchEmbeddingService.new(@workspace).similar_to("anything")

    assert_empty matches
  end

  test "a finding and a postmortem are searchable too" do
    stub_embedding
    investigation = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    finding = investigation.conclude!(summary: "The 14:02 deploy raised the pool size")

    SearchEmbeddingService.new(@workspace).write!(finding)

    assert_equal @workspace, finding.reload.search_embedding.workspace
    assert_match "pool size", finding.search_text
  end

  test "a row written by an older embedding model is not compared against a new one" do
    stub_embedding
    SearchEmbeddingService.new(@workspace).write!(@incident)
    @incident.search_embedding.update!(model: "some-older-model")

    assert_empty SearchEmbeddingService.new(@workspace).similar_to("anything")
  end

  test "a postmortem is embedded once it is written, not while it is being drafted" do
    stub_embedding
    postmortem = postmortems(:postmortem_resolved_ws1)

    postmortem.update!(status: Postmortem::STATUS_DRAFT)
    assert_no_enqueued_jobs(only: WriteSearchEmbeddingJob) { postmortem.update!(title: "Draft title") }

    assert_enqueued_with(job: WriteSearchEmbeddingJob) do
      postmortem.update!(status: Postmortem::STATUS_COMPLETED)
    end
  end

  test "a milestone noted on the channel puts the incident back in the queue" do
    assert_enqueued_with(job: WriteSearchEmbeddingJob) do
      @incident.incident_events.create!(
        event_type: IncidentEvent::MILESTONE_NOTED, metadata: { "statement" => "Diego suspected the deploy" }
      )
      @incident.update!(milestones_noted_through: "1.002")
    end
  end

  test "a record is embedded in the background when it changes" do
    assert_enqueued_with(job: WriteSearchEmbeddingJob) do
      @incident.update!(summary: "Now with more detail")
    end
  end

  private

  def near = Array.new(SearchEmbedding::DIMENSIONS) { |index| index.zero? ? 1.0 : 0.0 }

  def far = Array.new(SearchEmbedding::DIMENSIONS) { |index| index == 1 ? 1.0 : 0.0 }

  def embedding(vector) = Struct.new(:vectors, :model).new(vector, "text-embedding-3-small")

  # One vector per text, so what is near what is a fact of the test rather than a guess about a model.
  def stub_embedding(vectors: {})
    FirefightAi.stubs(:embed).returns(embedding(near))
    vectors.each do |text, vector|
      wanted = text.to_s.squish
      FirefightAi.stubs(:embed).with { |given, **| given.to_s.squish == wanted }.returns(embedding(vector))
    end
  end
end
