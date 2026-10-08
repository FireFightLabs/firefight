require "test_helper"

class ProviderDocChunk::SearchTest < ActiveSupport::TestCase
  setup do
    store_doc_page(provider: "northflank", path: "docs/workflows.md", content: <<~MARKDOWN)
      # Run and manage workflows

      ## Run a workflow using a webhook

      Send a GET or POST request to the URL to start a workflow run. Pass `release.sha` and `release.branch` as query parameters.

      ## Use cron schedules

      Workflows can run automatically on a repeating schedule.
    MARKDOWN
    store_doc_page(provider: "northflank", path: "docs/backups.md", content: "# Backups\n\nBack up an addon on a schedule and restore it.")
    store_doc_page(provider: "render", path: "debug/webhooks.md", content: "# Deploy hooks\n\nA deploy hook URL starts a deploy with release.sha.")
  end

  test "an exact name finds the section that holds it" do
    hits = search("release.sha", providers: [ "northflank" ]).hits

    assert_equal "Run and manage workflows > Run a workflow using a webhook", hits.first.chunk.heading_path
    assert_equal [ :words ], hits.first.matched_by
  end

  test "a question in other words finds the section by meaning, merged with what its words found" do
    webhook = chunk_at("Run and manage workflows > Run a workflow using a webhook")
    backup = chunk_at("Backups")
    embed(webhook, axis: 0)
    embed(backup, axis: 1)
    embed(chunk_at("Run and manage workflows > Use cron schedules"), axis: 2)

    hits = search("how do I kick off a deployment from my CI", providers: [ "northflank" ], meaning: -> { unit(0) }).hits

    assert_equal webhook.id, hits.first.chunk.id
    assert_includes hits.first.matched_by, :meaning
  end

  test "only the providers asked for are searched" do
    assert_equal %w[northflank], search("release.sha", providers: [ "northflank" ]).hits.map { |hit| hit.chunk.provider }.uniq
    assert_equal %w[render], search("release.sha", providers: [ "render" ]).hits.map { |hit| hit.chunk.provider }.uniq
    assert_empty search("release.sha", providers: []).hits
  end

  test "meaning is never asked for while no chunk of those providers has a vector from the model" do
    asked = false
    search("schedule", providers: [ "northflank" ], meaning: -> { asked = true }).hits

    assert_not asked
  end

  test "a snippet starts near the first word asked about" do
    chunk = chunk_at("Run and manage workflows > Run a workflow using a webhook")

    assert_match "release.sha", chunk.snippet([ "release.sha" ])
  end

  private

  def search(query, providers:, meaning: nil) = ProviderDocChunk::Search.new(query, providers: providers, model: "text-embedding-3-small", meaning: meaning)

  def chunk_at(heading_path) = ProviderDocChunk.find_by!(heading_path: heading_path)

  def unit(axis) = Array.new(ProviderDocChunk::DIMENSIONS) { |index| index == axis ? 1.0 : 0.0 }

  def embed(chunk, axis:) = chunk.update!(embedding: unit(axis), embedding_model: "text-embedding-3-small", embedded_digest: chunk.content_digest)
end
