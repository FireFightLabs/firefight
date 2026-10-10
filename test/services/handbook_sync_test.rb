require "test_helper"

class HandbookSyncTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Read = Integrations::Packs::CodeHost::Documents::Read
  File = Integrations::Packs::CodeHost::Documents::File

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "Acme code")
    @source = Chat::HandbookSource.create!(workspace: @workspace, integration: @github, kind: Chat::HandbookSource::KIND_REPOSITORY, repository: "acme/web", path: "docs/")
  end

  test "each file in the folder becomes a synced page, titled by its first heading, and a second read changes only what changed" do
    read(file("docs/release.md", "# Releasing\n\nTag main."), file("docs/owners.md", "Payments owns checkout."))

    pages = HandbookSync.new(@source).sync!

    assert_equal [ "Releasing", "Owners" ], pages.map(&:title)
    assert(pages.all?(&:synced?))
    assert_equal "https://github.com/acme/web/blob/main/docs/release.md", pages.first.source_url
    assert @source.reload.synced_at

    read(file("docs/release.md", "# Releasing\n\nTag main, then deploy."))
    HandbookSync.new(@source.reload).sync!

    release = Chat::HandbookPage.find_by!(workspace: @workspace, source_path: "docs/release.md")
    assert_equal [ "# Releasing\n\nTag main.", "# Releasing\n\nTag main, then deploy." ], release.wordings.map(&:text)
    assert_not Chat::HandbookPage.exists?(workspace: @workspace, source_path: "docs/owners.md")
  end

  test "a read that fails keeps every page and says why" do
    read(file("docs/release.md", "Tag main."))
    HandbookSync.new(@source).sync!
    Integrations::RepositoryDocuments.stubs(:read).raises(Integrations::Error, "acme/web has no text file at docs/ on main.")

    assert_nil HandbookSync.new(@source.reload).sync!

    assert_equal "acme/web has no text file at docs/ on main.", @source.reload.sync_error
    assert_equal 1, @source.pages.count
  end

  test "what a read left out is said, and a title another page holds gets a number" do
    handbook_page!(@workspace, "Releasing", "Written by hand")
    Integrations::RepositoryDocuments.stubs(:read).returns(Read.new(files: [ file("docs/release.md", "# Releasing\n\nTag main.") ], branch: "main",
                                                                    gaps: [ "docs/huge.md is over 200 KB and was not read." ]))

    page = HandbookSync.new(@source).sync!.sole

    assert_equal "Releasing (2)", page.title
    assert_equal "docs/huge.md is over 200 KB and was not read.", @source.reload.sync_error
  end

  test "a file that looks like it holds a secret is not brought in, and the source says so" do
    read(file("docs/release.md", "Tag main."), file("docs/db.md", "Connect with postgres://app:hunter2@db.internal/prod"))

    pages = HandbookSync.new(@source).sync!

    assert_equal [ "docs/release.md" ], pages.map(&:source_path)
    assert_match "docs/db.md was not brought in: text looks like it holds a secret", @source.reload.sync_error
  end

  test "a document is read through its connection's document reader" do
    notion = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "notion", name: "Notion")
    source = Chat::HandbookSource.create!(workspace: @workspace, integration: notion, kind: Chat::HandbookSource::KIND_DOCUMENT, reference: "https://notion.so/acme/Release-1")
    Integrations::Documents.stubs(:read).with(notion, "https://notion.so/acme/Release-1")
                           .returns(Integrations::Documents::Page.new(title: "Release guide", text: "Ship on Tuesdays.", url: "https://notion.so/acme/Release-1"))

    page = HandbookSync.new(source).sync!.sole

    assert_equal [ "Release guide", "Ship on Tuesdays.", Chat::HandbookPage::KIND_SYNCED ], [ page.title, page.text, page.kind ]
  end

  test "a push to the branch a source reads syncs it at once, and a push elsewhere does not" do
    @source.update!(branch: "main")
    push = Integrations::RepositoryDocuments::Push

    assert_enqueued_with(job: HandbookSyncJob, args: [ @source.id ]) { HandbookSync.pushed!([ @github ], [ push.new(repository: "Acme/Web", branch: "main") ]) }
    assert_no_enqueued_jobs(only: HandbookSyncJob) { HandbookSync.pushed!([ @github ], [ push.new(repository: "acme/web", branch: "feature") ]) }
  end

  test "the sweep reads every source not read within the hour" do
    fresh = Chat::HandbookSource.create!(workspace: @workspace, integration: @github, kind: Chat::HandbookSource::KIND_REPOSITORY, repository: "acme/api",
                                         path: "README.md", synced_at: 5.minutes.ago)

    HandbookSync.sweep!

    swept = enqueued_jobs.select { |job| job["job_class"] == HandbookSyncJob.name }.map { |job| job["arguments"].first }
    assert_includes swept, @source.id
    assert_not_includes swept, fresh.id
  end

  private

  def file(path, text) = File.new(path: path, content: text, url: "https://github.com/acme/web/blob/main/#{path}")

  def read(*files)
    Integrations::RepositoryDocuments.stubs(:read).returns(Read.new(files: files, branch: "main", gaps: []))
  end
end
