require "test_helper"

class ProviderDocs::EmbeddingTest < ActiveSupport::TestCase
  test "only chunks whose words changed since they were embedded are sent, on the deployment's model, with no workspace" do
    page = store_doc_page(provider: "northflank", path: "docs/workflows.md", content: "# Workflows\n\n## Webhook\n\nCopy the URL.\n\n## Cron\n\nA schedule.")
    sent = []
    FirefightAi.stubs(:embed_documents).with { |texts| sent << texts }.returns([ [ unit, unit ], "text-embedding-3-small" ])

    assert_equal 2, ProviderDocs::Embedding.run!(model: "text-embedding-3-small")
    assert_equal [ "Workflows > Cron\n\nA schedule.", "Workflows > Webhook\n\nCopy the URL." ], sent.sole.sort

    page.update!(content: "# Workflows\n\n## Webhook\n\nCopy the URL.\n\n## Cron\n\nAt most every ten minutes.")
    page.rechunk!
    FirefightAi.stubs(:embed_documents).with { |texts| sent << texts }.returns([ [ unit ], "text-embedding-3-small" ])

    assert_equal 1, ProviderDocs::Embedding.run!(model: "text-embedding-3-small")
    assert_equal [ "Workflows > Cron\n\nAt most every ten minutes." ], sent.last
    assert_equal 0, ProviderDocs::Embedding.run!(model: "text-embedding-3-small")
  end

  test "a document embedding is recorded in the ledger with no workspace, paid as the deployment's own" do
    vectors = Struct.new(:vectors, :model, :tokens).new([ unit ], "text-embedding-3-small", nil)
    RubyLLM.stubs(:embed).returns(vectors)

    found, model = FirefightAi.embed_documents([ "Workflows" ])

    assert_equal [ unit ], found
    assert_equal FirefightAi.embedding_model, model
    row = Inference.find_by!(feature: Inference::FEATURE_PROVIDER_DOCS)
    assert_nil row.workspace_id
    assert_equal Inference::PAID_BY_OPERATOR, row.paid_by
  end

  private

  def unit = Array.new(ProviderDocChunk::DIMENSIONS) { |index| index.zero? ? 1.0 : 0.0 }
end
