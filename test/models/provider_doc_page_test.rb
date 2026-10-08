require "test_helper"

class ProviderDocPageTest < ActiveSupport::TestCase
  PAGE = <<~MARKDOWN.freeze
    ---
    title: Run and manage workflows
    ---
    # Run and manage workflows

    Run a workflow by hand, from Git or on a schedule.

    ## Run a workflow using a webhook

    Treat the URL as a credential.

    ### Git trigger parameters

    | Parameter | Value |
    | `<git-trigger>.sha` | The commit SHA |

    ```bash
    # Not a heading inside a code sample
    curl "https://webhooks.northflank.com/workflows/TOKEN?release.sha=abc"
    ```

    ## View runs

    The state of the current run is in the header.
  MARKDOWN

  test "a page is split at its headings, each section carrying the headings above it, and a code sample's comment is not a heading" do
    page = store_doc_page(provider: "northflank", path: "docs/application/release/run-and-manage-workflows.md", content: PAGE)
    chunks = page.chunks.order(:position)

    assert_equal "Run and manage workflows", page.title
    assert_equal [ "Run and manage workflows", "Run and manage workflows > Run a workflow using a webhook",
                   "Run and manage workflows > Run a workflow using a webhook > Git trigger parameters", "Run and manage workflows > View runs" ],
                 chunks.map(&:heading_path)
    assert_includes chunks.third.text, "# Not a heading inside a code sample"
    assert_equal "northflank", chunks.first.provider
  end

  test "a long section is split between paragraphs, and a paragraph longer than a chunk between its lines" do
    paragraph = ([ "word" ] * 200).join(" ")
    table = (1..400).map { |row| "| row #{row} | value |" }.join("\n")
    page = store_doc_page(provider: "northflank", path: "docs/long.md", content: "# Long\n\n#{paragraph}\n\n#{paragraph}\n\n#{table}")

    pieces = page.chunks.order(:position).map(&:text)
    assert pieces.size >= 4
    assert pieces.all? { |text| text.split.size <= ProviderDocPage::Chunking::MAX_WORDS }
    assert_equal [ "Long" ], page.chunks.distinct.pluck(:heading_path)
  end

  test "splitting again keeps the embedding of every section whose words did not change, and drops the rest" do
    page = store_doc_page(provider: "northflank", path: "docs/workflows.md", content: PAGE)
    vector = Array.new(ProviderDocChunk::DIMENSIONS) { |index| index.zero? ? 1.0 : 0.0 }
    page.chunks.update_all(embedding: "[#{vector.join(',')}]", embedding_model: "text-embedding-3-small")
    page.chunks.each { |chunk| chunk.update_columns(embedded_digest: chunk.content_digest) }

    page.update!(content: PAGE.sub("The state of the current run is in the header.", "Runs are listed under View runs."))
    page.rechunk!

    kept = page.chunks.order(:position).to_a
    assert kept.first(3).all? { |chunk| chunk.embedding.present? && chunk.embedded_digest == chunk.content_digest }
    assert_nil kept.last.embedding
    assert_equal [ kept.last.id ], ProviderDocChunk.unembedded("text-embedding-3-small").pluck(:id)
  end

  test "a page with no title of its own is named by its file" do
    assert_equal "Error 522", ProviderDocPage.title_for("Some text", "errors/error-522.md")
    assert_equal "Purge cache", ProviderDocPage.title_for("# Purge cache\n\nText", "cache/purge.md")
  end
end
