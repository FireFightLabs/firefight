require "test_helper"

class ProviderDocs::SyncTest < ActiveSupport::TestCase
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

  test "reading a source reports how many pages it lists, what it skipped and failed, and the chunks it wrote" do
    ProviderDocs::Sync.run!(@definition, client: FakeWeb.new(INDEX => index("workflows", "builds"), page("workflows") => "# Workflows", page("builds") => "# Builds"))
    out = StringIO.new
    progress = ProviderDocs::Progress.new(out: out)
    progress.started([ "northflank_docs" ])

    ProviderDocs::Sync.run!(@definition, progress: progress, client: FakeWeb.new(INDEX => index("workflows", "builds", "runs"), page("workflows") => :unchanged,
                                                                                 page("builds") => :down, page("runs") => "# Runs\n\n## One\n\nA.\n\n## Two\n\nB."))

    assert_includes out.string, "northflank_docs  reading 3 pages\n"
    assert_match(/northflank_docs  done, 3 pages, 2 chunks written \(1 unchanged, 1 failed\) in \d+s/, out.string)
  end

  test "a source that cannot be read reports why" do
    out = StringIO.new
    progress = ProviderDocs::Progress.new(out: out)
    progress.started([ "northflank_docs" ])

    assert_raises(DocsClient::Error) { ProviderDocs::Sync.run!(@definition, progress: progress, client: FakeWeb.new(INDEX => :down)) }

    assert_includes out.string, "northflank_docs  could not be read: could not reach docs.example.com"
  end

  private

  def page(name) = "https://docs.example.com/v1/#{name}.md"

  def index(*names) = "# Docs\n\n#{names.map { |name| "- [#{name}](#{page(name)})" }.join("\n")}\n- [elsewhere](https://other.example.com/x.md)\n"

  def blob(path, sha) = { "path" => path, "type" => "blob", "sha" => sha }
end
