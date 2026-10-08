require "test_helper"

class ProviderDocs::ProgressTest < ActiveSupport::TestCase
  setup do
    @now = 0.0
    @out = StringIO.new
    @logged = []
    Rails.logger.stubs(:info).with { |line| record(line) }
    Rails.logger.stubs(:warn).with { |line| record(line) }
    @progress = ProviderDocs::Progress.new(out: @out, clock: -> { @now })
  end

  test "while reading a source it reports every fifty pages, and sooner when a quarter minute has passed" do
    @progress.started(%w[northflank_docs gitlab])
    @progress.source_started("northflank_docs")
    @progress.listed(120)
    49.times { @progress.page(:unchanged) }
    @progress.page(:changed)
    @now = 20.0
    @progress.page(:failed)
    48.times { @progress.page(:changed) }
    @progress.page(:changed)
    19.times { @progress.page(:changed) }

    assert_equal [ "Reading 2 sources", "northflank_docs  reading 120 pages", "northflank_docs  reading 50/120 pages (49 unchanged)",
                   "northflank_docs  reading 51/120 pages (49 unchanged, 1 failed)", "northflank_docs  reading 100/120 pages (49 unchanged, 1 failed)" ], lines
    reading = @logged.select { |entry| entry["event"] == "provider_docs.reading" }
    assert_equal [ 50, 51, 100 ], reading.pluck("read")
    assert_equal({ "event" => "provider_docs.reading", "source" => "northflank_docs", "read" => 100, "pages" => 120, "unchanged" => 49, "failed" => 1 }, reading.last)
  end

  test "a finished source says its pages, the chunks it wrote and how long it took" do
    @progress.started(%w[northflank_docs])
    @progress.source_started("northflank_docs")
    @progress.listed(2)
    @progress.page(:changed)
    @progress.page(:unchanged)
    @now = 412.4

    @progress.source_finished(ProviderDocSource.new(page_count: 2, version: "v1"), chunks: 1_234)

    assert_equal "northflank_docs  done, 2 pages, 1,234 chunks written (1 unchanged) in 6m 52s", lines.last
    assert_equal({ "event" => "provider_docs.read", "source" => "northflank_docs", "pages" => 2, "version" => "v1", "chunks" => 1_234,
                   "unchanged" => 1, "pages_failed" => 0, "failed" => false, "seconds" => 412.4 }, @logged.last)
  end

  test "embedding reports in batches, then the whole run is summed up" do
    @progress.started(%w[northflank_docs gitlab])
    @progress.source_started("northflank_docs")
    @progress.listed(3)
    3.times { @progress.page(:changed) }
    @progress.source_finished(ProviderDocSource.new(page_count: 3), chunks: 2_500)
    @progress.source_started("gitlab")
    @progress.source_failed(DocsClient::Error.new("could not reach docs.gitlab.com"))

    @progress.embedding_started(2_500)
    (100..2_500).step(100) { |done| @progress.embedded(done) }
    @progress.embedding_finished(2_500)
    @now = 4_000.0
    @progress.finished

    assert_includes lines, "#{'gitlab'.ljust(15)}  could not be read: could not reach docs.gitlab.com"
    assert_equal [ "Embedding 2,500 chunks", "Embedding 1000/2500 chunks", "Embedding 2000/2500 chunks", "Embedded 2,500 chunks in 0s",
                   "Done in 1h 6m: 1 source read, 1 could not be read, 3 pages, 2,500 chunks written, 2,500 embedded" ], lines.last(5)
    assert_equal({ "event" => "provider_docs.finished", "sources" => 1, "unread" => 1, "pages" => 3, "chunks" => 2_500, "embedded" => 2_500, "seconds" => 4_000.0 }, @logged.last)
  end

  test "without a terminal it only logs" do
    progress = ProviderDocs::Progress.new(clock: -> { @now })
    progress.started(%w[northflank_docs])
    progress.embedding_failed(StandardError.new("no key"))
    progress.missing_guides({ "northflank_fixes" => %w[docs/gone.md] })

    assert_equal %w[provider_docs.started provider_docs.unembedded provider_docs.missing_guides], @logged.pluck("event")
    assert_equal({ "northflank_fixes" => %w[docs/gone.md] }, @logged.last["guides"])
  end

  private

  def lines = @out.string.lines(chomp: true)

  def record(line)
    @logged << JSON.parse(line) if line.to_s.start_with?('{"event":"provider_docs.')
    true
  end
end
