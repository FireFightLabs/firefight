require "test_helper"

class ProviderDocsSyncJobTest < ActiveSupport::TestCase
  test "every source is read, one that fails leaves the rest to carry on, and what changed is embedded" do
    read = []
    ProviderDocs::Sync.stubs(:run!).with do |definition, **|
      read << definition.key
      raise DocsClient::Error, "could not reach northflank.com" if definition.key == "northflank_docs"

      true
    end.returns(ProviderDocSource.new(page_count: 1))
    ProviderDocs::Embedding.expects(:run!).returns(0)

    ProviderDocsSyncJob.perform_now

    assert_equal ProviderDocSource::Definition.all.map(&:key), read
  end

  test "on first boot only the sources never read are read, and nothing when all have been" do
    keys = ProviderDocSource::Definition.all.map(&:key)
    (keys - [ "northflank_docs" ]).each { |key| ProviderDocSource.create!(key: key, provider: ProviderDocSource::Definition.find(key).provider, fetched_at: Time.current) }
    read = []
    ProviderDocs::Sync.stubs(:run!).with { |definition, **| read << definition.key }.returns(ProviderDocSource.new)
    ProviderDocs::Embedding.stubs(:run!).returns(0)

    ProviderDocsSyncJob.perform_now(true)
    assert_equal [ "northflank_docs" ], read

    ProviderDocSource.create!(key: "northflank_docs", provider: "northflank", fetched_at: Time.current)
    ProviderDocs::Sync.expects(:run!).never
    ProviderDocsSyncJob.perform_now(true)
  end

  test "a named source is read alone" do
    read = []
    ProviderDocs::Sync.stubs(:run!).with { |definition, **| read << definition.key }.returns(ProviderDocSource.new)
    ProviderDocs::Embedding.stubs(:run!).returns(0)

    ProviderDocsSyncJob.perform_now(source: "northflank_docs")

    assert_equal [ "northflank_docs" ], read
  end

  test "a key read an API index lists that the reference just read no longer does is warned of, and nothing when the store lacks the reference" do
    ProviderDocs::Sync.stubs(:run!).returns(ProviderDocSource.new)
    ProviderDocs::Embedding.stubs(:run!).returns(0)
    out = StringIO.new

    ProviderDocsSyncJob.perform_now(source: "github_api", progress: ProviderDocs::Progress.new(out: out))
    assert_no_match "Key reads API indexes list", out.string

    content = "# actions\n\n## GET /repos/{owner}/{repo}/actions/runs\n\nList workflow runs\n"
    source = ProviderDocSource.create!(key: "github_api", provider: "github", fetched_at: Time.current)
    ProviderDocPage.create!(source: source, provider: "github", path: "api/actions.md", url: "https://example.com", title: "actions",
                            content: content, content_digest: ProviderDocPage.digest_for(content), fetched_at: Time.current)
    Rails.logger.expects(:warn).at_least_once
    Rails.logger.expects(:warn).with { |line| line.include?("provider_docs.stale_api_indexes") }

    ProviderDocsSyncJob.perform_now(source: "github_api", progress: ProviderDocs::Progress.new(out: out))

    assert_match "Key reads API indexes list that the reference no longer does", out.string
    assert_match "github (GET /repos/{owner}/{repo}/actions/workflows", out.string
  end

  test "an embedding model that cannot be reached leaves the store searched by its words" do
    ProviderDocs::Sync.stubs(:run!).returns(ProviderDocSource.new)
    ProviderDocs::Embedding.stubs(:run!).raises(FirefightAi::TerminalError.new("no key", reason: "ConfigurationError"))

    assert_nothing_raised { ProviderDocsSyncJob.perform_now }
  end
end
