require "test_helper"

class SearchDocumentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!(environment: catalog_entries(:production_env))
  end

  test "a resource is found by its name, id, account, details, tags, the services it runs and their owners" do
    ResourceMap.record!(@row, snapshot(found("payments-api", details: { "region" => "eu-west-1", "instances" => 3, ResourceMap::TAGS => { "team" => "ledger" } })))
    resource = resource("payments-api")
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: resource)

    SearchDocument.index!(ResourceMap::Resource, [ resource.id ])

    document = SearchDocument.find_by!(searchable: resource)
    assert_equal "payments-api", document.title
    %w[payments-api acme/shop eu-west-1 team=ledger ledger auth platform service northflank].each do |word|
      assert matches?(document, word), "#{word} should find the resource"
    end
    assert_not matches?(document, "3"), "only words in details are searched"
    assert_equal({ "kind" => "service", "provider" => "northflank", "environments" => [ "Production" ], "names" => [ "payments-api", "acme/shop" ] }, document.facets)
    assert_equal "payments-api acme/shop", document.trigram_text
    assert_equal [ "name", "catalog" ], resource.search_document_matched([ "payments", "auth" ]) - [ "details" ]
  end

  test "ids and names are kept as written, never stemmed" do
    ResourceMap.record!(@row, snapshot(found("databases-running", name: "orders")))
    SearchDocument.index!(ResourceMap::Resource, [ resource("databases-running").id ])
    document = SearchDocument.find_by!(searchable: resource("databases-running"))

    assert matches?(document, "databases")
    assert matches?(document, "running")
    assert_not matches?(document, "database")
    assert_not matches?(document, "run")
  end

  test "a row is rewritten only when what it says changes" do
    ResourceMap.record!(@row, snapshot(found("web")))
    SearchDocument.index!(ResourceMap::Resource, [ resource("web").id ])
    document = SearchDocument.find_by!(searchable: resource("web"))
    document.update_columns(updated_at: 1.day.ago)

    SearchDocument.index!(ResourceMap::Resource, [ resource("web").id ])
    assert_in_delta 1.day.ago, document.reload.updated_at, 1.minute

    resource("web").update!(name: "storefront")
    SearchDocument.index!(ResourceMap::Resource, [ resource("web").id ])
    assert_equal "storefront", document.reload.title
    assert_in_delta Time.current, document.updated_at, 1.minute
  end

  test "a sweep queues one job for everything it changed, and a sweep that changed nothing queues none" do
    Integrations::NativeExecutor.stubs(:map_of).returns(snapshot(found("web"), found("worker"), found("db", kind: ResourceMap::KIND_DATABASE)))

    assert_enqueued_jobs 1, only: SearchDocumentIndexJob do
      Integrations::MapSweep.run!(@row)
    end
    queued = enqueued_jobs.find { |job| job["job_class"] == SearchDocumentIndexJob.name }
    assert_equal %w[db web worker], ResourceMap::Resource.where(id: queued["arguments"].last).pluck(:name).sort
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: SearchDocumentIndexJob) { Integrations::MapSweep.run!(@row) }

    Integrations::NativeExecutor.stubs(:map_of).returns(snapshot(found("web", name: "storefront"), found("worker"), found("db", kind: ResourceMap::KIND_DATABASE)))
    assert_enqueued_with(job: SearchDocumentIndexJob, args: [ ResourceMap::Resource.name, [ resource("web").id ] ]) do
      Integrations::MapSweep.run!(@row)
    end
  end

  test "a resource the sweep no longer sees is queued too" do
    ResourceMap.record!(@row, snapshot(found("web"), found("worker")))

    assert_equal [ resource("worker").id ], ResourceMap.record!(@row, snapshot(found("web")))
  end

  test "a catalog entry is indexed as it is saved, with what it is for, what people wrote on it and who owns it" do
    entry = catalog_entries(:auth_service)

    entry.update!(name: "Identity")

    document = SearchDocument.find_by!(searchable: entry)
    assert_equal "Identity", document.title
    %w[identity auth_service authentication critical platform service].each { |word| assert matches?(document, word), word }
    assert_equal "Service", document.facets["catalog_type"]
  end

  test "renaming a team reaches the services it owns and the resources they run on" do
    team = catalog_entries(:platform_team)
    service = catalog_entries(:auth_service)
    ResourceMap.record!(@row, snapshot(found("web")))
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: service, resource: resource("web"))
    SearchDocument.index!(ResourceMap::Resource, [ resource("web").id ])
    SearchDocument.index!(CatalogEntry, [ service.id ])

    perform_enqueued_jobs(only: SearchDocumentIndexJob) { team.update!(name: "Core Infrastructure") }

    assert matches?(SearchDocument.find_by!(searchable: resource("web")), "infrastructure")
    assert matches?(SearchDocument.find_by!(searchable: service), "infrastructure")
    assert_not matches?(SearchDocument.find_by!(searchable: service), "platform")
  end

  test "an archived entry leaves search, and so does it from what it owned" do
    team = catalog_entries(:platform_team)
    service = catalog_entries(:auth_service)
    SearchDocument.index!(CatalogEntry, [ team.id, service.id ])

    perform_enqueued_jobs(only: SearchDocumentIndexJob) { team.soft_delete! }

    assert_not SearchDocument.exists?(searchable: team)
    assert_not matches?(SearchDocument.find_by!(searchable: service), "platform")
  end

  test "linking a resource to a service queues it to be indexed again" do
    ResourceMap.record!(@row, snapshot(found("web")))

    assert_enqueued_with(job: SearchDocumentIndexJob, args: [ ResourceMap::Resource.name, [ resource("web").id ] ]) do
      ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: resource("web"))
    end
  end

  test "rewiring a connection row to another environment queues what it reports" do
    ResourceMap.record!(@row, snapshot(found("web")))

    assert_enqueued_with(job: SearchDocumentIndexJob, args: [ ResourceMap::Resource.name, [ resource("web").id ] ]) do
      @row.update!(environment: catalog_entries(:development_env))
    end
    perform_enqueued_jobs(only: SearchDocumentIndexJob)
    assert_equal [ "Development" ], SearchDocument.find_by!(searchable: resource("web")).facets["environments"]
  end

  test "the backfill indexes what has no row, embeds a catalog entry once, and writes nothing for a memory" do
    ResourceMap.record!(@row, snapshot(found("web")))
    Chat::Memory.create!(workspace: @workspace, text: "The ledger database is the source of truth", state: Chat::Memory::STATE_CONFIRMED)
    SearchDocument.delete_all

    assert_enqueued_with(job: WriteSearchEmbeddingJob, args: [ CatalogEntry.name, catalog_entries(:auth_service).id ]) do
      SearchDocumentBackfillJob.perform_now
    end

    assert SearchDocument.exists?(searchable: resource("web"))
    assert SearchDocument.exists?(searchable: catalog_entries(:auth_service))
    assert_not SearchDocument.exists?(searchable: catalog_entries(:deleted_entry))
    assert_equal SearchDocument::TYPES.sort, SearchDocument.distinct.pluck(:searchable_type).sort
    assert_not SearchDocument.where("document @@ to_tsquery('simple', 'truth')").exists?
    assert_no_enqueued_jobs(only: WriteSearchEmbeddingJob) { SearchDocumentBackfillJob.perform_now }
  end

  test "a catalog entry is embedded from its name, type and what it is for" do
    entry = catalog_entries(:auth_service)

    assert_equal "Auth Service (Service)\nHandles authentication.\nCritical", entry.search_text
    assert entry.search_embeddable?
    assert_not catalog_entries(:vendor_acme).search_embeddable?
  end

  private

  def found(id, name: id, kind: ResourceMap::KIND_SERVICE, details: {})
    ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: kind, external_id: id, name: name, status: "running", details: details)
  end

  def snapshot(*resources) = ResourceMap::Snapshot.new(resources: resources)

  def resource(external_id) = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: external_id)

  def matches?(document, word)
    SearchDocument.where(id: document.id).where("document @@ to_tsquery('simple', ?)", ActiveRecord::Base.connection.quote(word)).exists?
  end
end
