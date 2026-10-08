require "test_helper"

class ProviderDocs::SyncTest < ActiveSupport::TestCase
  # Answers like the web would, from a table of address to text. An address answering :gone is a 404, :down cannot be
  # reached, and :unchanged a 304 for the revision it was asked with.
  class FakeWeb
    attr_reader :asked

    def initialize(answers)
      @answers = answers
      @asked = []
    end

    def page(url, revision: nil) = answer(url, revision)

    def file(url, revision: nil, headers: {}) = answer(url, revision)

    def json(url, headers: {}) = JSON.parse(answer(url, nil).body)

    private

    def answer(url, revision)
      @asked << url
      found = @answers.fetch(url) { raise DocsClient::NotFound, "#{url} answered 404" }
      raise DocsClient::NotFound, "#{url} answered 404" if found == :gone
      raise DocsClient::Error, "could not reach #{URI.parse(url).host}" if found == :down
      raise DocsClient::TooLarge, "#{url} is larger than 3 MB" if found == :huge
      return DocsClient::Answer.new(body: nil, revision: revision, url: url) if found == :unchanged

      DocsClient::Answer.new(body: found, revision: "\"#{Digest::SHA1.hexdigest(found)}\"", url: url)
    end
  end

  INDEX = "https://docs.example.com/llms.txt".freeze

  setup do
    @definition = ProviderDocSource::Definition.new(key: "northflank_docs", provider: "northflank", kind: "index",
                                                    settings: { "index" => INDEX, "under" => "https://docs.example.com/v1/", "suffix" => ".md", "to" => "docs" })
  end

  test "an index source reads each page it lists, splits it into chunks, and keeps where it came from" do
    web = FakeWeb.new(INDEX => index("workflows", "builds"), page("workflows") => "# Workflows\n\n## Webhook trigger\n\nCopy the URL.",
                      page("builds") => "# Builds\n\nA build.")

    source = ProviderDocs::Sync.run!(@definition, client: web)

    assert_equal %w[docs/builds.md docs/workflows.md], ProviderDocPage.paths_of("northflank")
    workflows = ProviderDocPage.named("northflank", "docs/workflows.md")
    assert_equal page("workflows"), workflows.url
    assert_equal [ "Workflows > Webhook trigger" ], workflows.chunks.pluck(:heading_path)
    assert_equal 2, source.page_count
    assert source.fetched_at
    assert_nil source.error
  end

  test "a page the source no longer lists is removed, and one that did not change is not written again" do
    ProviderDocs::Sync.run!(@definition, client: FakeWeb.new(INDEX => index("workflows", "builds"), page("workflows") => "# Workflows", page("builds") => "# Builds"))
    kept = ProviderDocPage.named("northflank", "docs/workflows.md")

    ProviderDocs::Sync.run!(@definition, client: FakeWeb.new(INDEX => index("workflows"), page("workflows") => :unchanged))

    assert_equal %w[docs/workflows.md], ProviderDocPage.paths_of("northflank")
    assert_equal kept.updated_at, kept.reload.updated_at
    assert_equal "# Workflows", kept.content
  end

  test "a page that cannot be read keeps the copy it had, and the source says which" do
    ProviderDocs::Sync.run!(@definition, client: FakeWeb.new(INDEX => index("workflows"), page("workflows") => "# Workflows\n\nOld."))

    source = ProviderDocs::Sync.run!(@definition, client: FakeWeb.new(INDEX => index("workflows"), page("workflows") => :down))

    assert_equal "# Workflows\n\nOld.", ProviderDocPage.named("northflank", "docs/workflows.md").content
    assert_match "1 page could not be read and kept the copy they had. docs/workflows.md: could not reach docs.example.com", source.error
  end

  test "a page too large to read is left out without counting as a failure" do
    source = ProviderDocs::Sync.run!(@definition, client: FakeWeb.new(INDEX => index("workflows", "schema"), page("workflows") => "# Workflows", page("schema") => :huge))

    assert_equal %w[docs/workflows.md], ProviderDocPage.paths_of("northflank")
    assert_nil source.error
  end

  test "a source that cannot be read at all keeps every page and records why" do
    ProviderDocs::Sync.run!(@definition, client: FakeWeb.new(INDEX => index("workflows"), page("workflows") => "# Workflows"))
    read_at = ProviderDocSource.find_by!(key: "northflank_docs").fetched_at

    assert_raises(DocsClient::Error) { ProviderDocs::Sync.run!(@definition, client: FakeWeb.new(INDEX => :down)) }

    source = ProviderDocSource.find_by!(key: "northflank_docs")
    assert_equal %w[docs/workflows.md], ProviderDocPage.paths_of("northflank")
    assert_equal read_at, source.fetched_at
    assert_equal "could not reach docs.example.com", source.error
  end

  test "a repository source reads only the files whose content changed since it last read them" do
    definition = ProviderDocSource::Definition.new(key: "planetscale", provider: "planetscale", kind: "repository",
                                                   settings: { "repository" => "https://github.com/planetscale/database-skills", "license" => "LICENSE",
                                                               "paths" => { "skills/postgres/references" => "postgres" } })
    tree = ->(sha) { { "sha" => "abc", "truncated" => false, "tree" => [ blob("LICENSE", "l1"), blob("skills/postgres/references/locks.md", sha),
                                                                          blob("skills/postgres/references/deeper/no.md", "x"), blob("README.md", "r") ] }.to_json }
    raw = "https://raw.githubusercontent.com/planetscale/database-skills/HEAD"
    first = FakeWeb.new("https://api.github.com/repos/planetscale/database-skills/git/trees/HEAD?recursive=1" => tree.call("s1"),
                        "#{raw}/skills/postgres/references/locks.md" => "# Locks", "#{raw}/LICENSE" => "MIT License")

    source = ProviderDocs::Sync.run!(definition, client: first)
    assert_equal %w[postgres/locks.md], ProviderDocPage.paths_of("planetscale")
    assert_equal "MIT License", source.license
    assert_equal "https://github.com/planetscale/database-skills/blob/HEAD/skills/postgres/references/locks.md", ProviderDocPage.named("planetscale", "postgres/locks.md").url

    again = FakeWeb.new("https://api.github.com/repos/planetscale/database-skills/git/trees/HEAD?recursive=1" => tree.call("s1"), "#{raw}/LICENSE" => "MIT License")
    ProviderDocs::Sync.run!(definition, client: again)
    assert_not_includes again.asked, "#{raw}/skills/postgres/references/locks.md"
  end

  private

  def page(name) = "https://docs.example.com/v1/#{name}.md"

  def index(*names) = "# Docs\n\n#{names.map { |name| "- [#{name}](#{page(name)})" }.join("\n")}\n- [elsewhere](https://other.example.com/x.md)\n"

  def blob(path, sha) = { "path" => path, "type" => "blob", "sha" => sha }
end
