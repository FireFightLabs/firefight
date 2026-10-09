require "test_helper"

class ResourceMapTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @row = connection("northflank")
  end

  test "a repository is found by its code host's address, whichever provider names it, and an address on no known host is not" do
    github = ResourceMap.repository_of("https://github.com/acme/web.git")
    gitlab = ResourceMap.repository_of("https://gitlab.com/acme/platform/api/")

    assert_equal [ "github", "acme", ResourceMap::KIND_REPOSITORY, "acme/web", "https://github.com/acme/web" ],
                 [ github.provider, github.account, github.kind, github.external_id, github.url ]
    assert_equal [ "gitlab", "acme", "acme/platform/api" ], [ gitlab.provider, gitlab.account, gitlab.external_id ]
    assert_equal github.key, ResourceMap.repository("github", "acme/web").key
    assert_nil ResourceMap.repository_of("https://git.example.com/acme/web")
    assert_nil ResourceMap.repository_of("https://github.com/acme")
    assert_nil ResourceMap.repository_of("not a url at all")
    assert_nil ResourceMap.repository("linear", "acme/web")
  end

  test "a gap names the kinds it could not read, and a sweep never takes a resource of one of them as gone" do
    ResourceMap.record!(@row, snapshot(found(ResourceMap::KIND_SERVICE, "web"), found(ResourceMap::KIND_JOB, "nightly")))
    gap = ResourceMap::Gap.new(text: "Jobs could not be read: 503.", kinds: [ ResourceMap::KIND_JOB ])

    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ found(ResourceMap::KIND_SERVICE, "web") ], gaps: [ gap ]))

    assert_nil ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "nightly").removed_at
    assert_equal [ "Jobs could not be read: 503." ], @row.reload.map_gaps
    error = assert_raises(ArgumentError) { ResourceMap::Snapshot.new(resources: [], gaps: [ "Jobs could not be read" ]) }
    assert_match "names the kinds it could not read", error.message
  end

  test "Firefight's own status words read as one health each, and a word in no list reads unknown" do
    health = ->(status) { ResourceMap::Resource.new(status: status).health }

    assert_equal %w[ok busy busy failing unknown], [ "running", "paused", "stopped", "unavailable", "scaled down" ].map(&health)
  end

  test "a sweep puts what the connection reaches on the map, with the links it declares" do
    ResourceMap.record!(@row, snapshot(web, repository, links: [ link(web, repository, ResourceMap::RELATION_BUILT_FROM) ], gaps: [ ResourceMap::Gap.new(text: "Jobs could not be read", kinds: []) ]))

    service = resource("web")
    assert_equal "running", service.status
    assert_equal @row, service.integration_environment
    assert_equal [ [ "web", ResourceMap::RELATION_BUILT_FROM, "acme/app" ] ],
                 ResourceMap::Link.where(workspace: @workspace).map { |each| [ each.from_resource.external_id, each.relation, each.to_resource.external_id ] }
    assert_equal ResourceMap::ORIGIN_DECLARED, service.links_out.sole.origin
    assert_equal [ "Jobs could not be read" ], @row.reload.map_gaps
    assert @row.map_swept_at
  end

  test "what a connection no longer reports is marked removed, and comes back with its first sighting kept" do
    ResourceMap.record!(@row, snapshot(web), at: 2.days.ago)
    first_seen = resource("web").first_seen_at

    ResourceMap.record!(@row, snapshot)
    assert resource("web").removed_at

    ResourceMap.record!(@row, snapshot(web))
    assert_nil resource("web").removed_at
    assert_equal first_seen, resource("web").first_seen_at
  end

  test "a sweep replaces its own links and keeps a person's" do
    ResourceMap.record!(@row, snapshot(web, repository, links: [ link(web, repository, ResourceMap::RELATION_BUILT_FROM) ]))
    ResourceMap::Link.create!(workspace: @workspace, from_resource: resource("web"), to_resource: resource("acme/app"),
                              relation: ResourceMap::RELATION_USES, origin: ResourceMap::ORIGIN_PERSON, last_seen_at: Time.current)

    ResourceMap.record!(@row, snapshot(web, repository))

    assert_equal [ ResourceMap::ORIGIN_PERSON ], resource("web").links_out.map(&:origin)
  end

  test "a sweep records what changed: what appeared, a new running commit, a status that moved, and what is gone" do
    ResourceMap.record!(@row, snapshot(deployed("aaa", "running")), at: 1.hour.ago)
    ResourceMap.record!(@row, snapshot(deployed("bbb", "failed")))
    ResourceMap.record!(@row, snapshot)

    changes = resource("web").changes_seen.order(:happened_at, :kind).map { |change| [ change.kind, change.from_value, change.to_value ] }
    assert_equal [ [ ResourceMap::Change::KIND_APPEARED, nil, nil ], [ ResourceMap::Change::KIND_DEPLOYED, "aaa", "bbb" ],
                   [ ResourceMap::Change::KIND_STATUS_CHANGED, "running", "failed" ], [ ResourceMap::Change::KIND_REMOVED, nil, nil ] ].sort_by(&:first),
                 changes.sort_by(&:first)
  end

  test "a rename is recorded as a change, and what was remembered about the resource is flagged as possibly outdated" do
    ResourceMap.record!(@row, snapshot(web), at: 1.hour.ago)
    memory = Chat::Memory.create!(workspace: @workspace, text: "web serves checkout", subject: resource("web"), state: Chat::Memory::STATE_CONFIRMED)
    renamed = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "storefront", status: "running")

    ResourceMap.record!(@row, snapshot(renamed))

    change = resource("web").changes_seen.find_by!(kind: ResourceMap::Change::KIND_RENAMED)
    assert_equal [ "web", "storefront" ], [ change.from_value, change.to_value ]
    assert_equal [ Chat::Memory::STATE_OUTDATED, "web was renamed storefront" ], [ memory.reload.state, memory.state_reason ]
  end

  test "what was remembered about a resource the connection stops reporting is flagged, and a rejected memory stays rejected" do
    ResourceMap.record!(@row, snapshot(web), at: 1.hour.ago)
    used = Chat::Memory.create!(workspace: @workspace, text: "web serves checkout", subject: resource("web"), state: Chat::Memory::STATE_UNCONFIRMED)
    rejected = Chat::Memory.create!(workspace: @workspace, text: "web is in Frankfurt", subject: resource("web"), state: Chat::Memory::STATE_REJECTED)

    ResourceMap.record!(@row, snapshot)

    assert_equal Chat::Memory::STATE_OUTDATED, used.reload.state
    assert_equal "web is no longer reported by its connection", used.state_reason
    assert_equal Chat::Memory::STATE_REJECTED, rejected.reload.state
  end

  test "a resource that comes back lifts the flag its removal set, and leaves what a person decided since" do
    ResourceMap.record!(@row, snapshot(web), at: 2.hours.ago)
    lifted = Chat::Memory.create!(workspace: @workspace, text: "web serves checkout", subject: resource("web"), state: Chat::Memory::STATE_CONFIRMED)
    decided = Chat::Memory.create!(workspace: @workspace, text: "web runs two instances", subject: resource("web"), state: Chat::Memory::STATE_UNCONFIRMED)
    ResourceMap.record!(@row, snapshot, at: 1.hour.ago)
    decided.reload.reject!(by: workspace_memberships(:alice_workspace_one), reason: "It runs one")

    ResourceMap.record!(@row, snapshot(web))

    assert_equal [ Chat::Memory::STATE_CONFIRMED, nil ], lifted.reload.values_at(:state, :state_reason)
    assert_equal Chat::Memory::STATE_REJECTED, decided.reload.state
  end

  test "a hostname's account is its registered domain, under a two label suffix too" do
    assert_equal "acme.com", ResourceMap.domain("app.acme.com").account
    assert_equal "acme.co.uk", ResourceMap.domain("api.acme.co.uk").account
    assert_equal "example.com.au", ResourceMap.domain("shop.example.com.au").account
    assert_equal "corp.internal", ResourceMap.domain("db.corp.internal").account
  end

  test "a link reaches something another connection reported, and a hostname both name keeps what each said" do
    web = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")
    app = ResourceMap.domain("app.acme.com")
    ResourceMap.record!(@row, snapshot(web, app.with(details: { "port" => 443 }), links: [ link(app, web, ResourceMap::RELATION_SERVED_BY) ]))
    cloudflare = connection("cloudflare_one")
    zone = ResourceMap::Found.new(provider: "cloudflare", account: "Acme", kind: ResourceMap::KIND_ZONE, external_id: "z1", name: "acme.com")
    edge = ResourceMap.domain("edge.acme.com")

    ResourceMap.record!(cloudflare, snapshot(zone, app.with(details: { "record" => "CNAME" }), edge,
                                             links: [ link(app, zone, ResourceMap::RELATION_PART_OF), link(edge, web, ResourceMap::RELATION_SERVED_BY) ]))

    assert_equal({ "port" => 443, "record" => "CNAME" }, resource("app.acme.com").details)
    assert ResourceMap::Link.exists?(from_resource: resource("edge.acme.com"), to_resource: resource("web"), integration_environment: cloudflare)
  end

  test "a resource two connections report stays while either does, and each keeps what it said" do
    web = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")
    app = ResourceMap.domain("app.acme.com")
    cloudflare = connection("cloudflare_two")
    ResourceMap.record!(@row, snapshot(web, app.with(details: { "port" => 443 })))
    ResourceMap.record!(cloudflare, snapshot(app.with(details: { "record" => "CNAME" })))

    ResourceMap.record!(@row, snapshot(web))
    assert_nil resource("app.acme.com").removed_at
    assert_equal({ "record" => "CNAME" }, resource("app.acme.com").details)

    ResourceMap.record!(cloudflare, snapshot)
    assert resource("app.acme.com").removed_at
  end

  test "what a sweep could not read in full is not taken as gone, nor are its links" do
    web = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")
    app = ResourceMap.domain("app.acme.com")
    ResourceMap.record!(@row, snapshot(web, app, links: [ link(app, web, ResourceMap::RELATION_SERVED_BY) ]))

    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ web ], gaps: [ ResourceMap::Gap.new(text: "Hostnames could not be read.", kinds: [ ResourceMap::KIND_DOMAIN ]) ]))

    assert_nil resource("app.acme.com").removed_at
    assert ResourceMap::Link.exists?(from_resource: resource("app.acme.com"), to_resource: resource("web"))
  end

  test "a partial read never removes a resource or a link, of any kind, and only a complete read does" do
    ResourceMap.record!(@row, snapshot(web, repository, found(ResourceMap::KIND_JOB, "nightly"), links: [ link(web, repository, ResourceMap::RELATION_BUILT_FROM) ]))
    partial = ResourceMap::Gap.new(text: "Domains could not be read.", kinds: [ ResourceMap::KIND_DOMAIN ])

    ResourceMap.record!(@row, snapshot(gaps: [ partial ]))

    assert_nil resource("web").removed_at
    assert_nil resource("acme/app").removed_at
    assert_nil resource("nightly").removed_at
    assert ResourceMap::Link.exists?(from_resource: resource("web"), to_resource: resource("acme/app"))
    assert_equal [ "Domains could not be read." ], @row.reload.map_gaps

    ResourceMap.record!(@row, snapshot(web, gaps: [ ResourceMap::Gap.new(text: "The SSL mode could not be read.", kinds: []) ]))

    assert_nil resource("web").removed_at
    assert resource("nightly").removed_at, "a gap that holds back no resource does not stop a removal"
    assert_not ResourceMap::Link.exists?(from_resource: resource("web"), to_resource: resource("acme/app"))
  end

  test "a setting that moves is a change naming the setting, and one read for the first time is not" do
    first = ResourceMap::Found.new(provider: "cloudflare", account: "Acme", kind: ResourceMap::KIND_ZONE, external_id: "z1", name: "acme.com")
    ResourceMap.record!(@row, snapshot(first), at: 2.hours.ago)
    ResourceMap.record!(@row, snapshot(first.with(details: { "waf_rules" => 3 })), at: 1.hour.ago)
    ResourceMap.record!(@row, snapshot(first.with(details: { "waf_rules" => 4 })))

    change = resource("z1").changes_seen.find_by!(kind: ResourceMap::Change::KIND_CONFIGURED)
    assert_equal [ "WAF custom rules", "3", "4" ], [ change.detail, change.from_value, change.to_value ]
  end

  test "what a provider reported is named for a person, in reading order, with the running commit shortened" do
    facts = ResourceMap.facts("deployed_commit" => "c4e4267d46e638ac", "plan" => "nf-compute-100-2", "production" => true, "appId" => "/team/p/web")

    assert_equal [ [ "Plan", "nf-compute-100-2" ], [ "Running commit", "c4e4267" ], [ "Production", "Yes" ] ], facts
  end

  test "a provider's status reads as healthy, busy, failing or unknown, and in words" do
    resource = ResourceMap::Resource.new(status: "in_progress")

    assert_equal ResourceMap::Resource::HEALTH_BUSY, resource.health
    assert_equal "In progress", resource.status_label
    assert_equal ResourceMap::Resource::HEALTH_OK, ResourceMap::Resource.new(status: "COMPLETED").health
    assert_equal ResourceMap::Resource::HEALTH_FAILING, ResourceMap::Resource.new(status: "failed").health
    assert_equal ResourceMap::Resource::HEALTH_UNKNOWN, ResourceMap::Resource.new(status: "sleepy").health
  end

  test "a resource two connections report is one resource" do
    other = connection("northflank_two")
    ResourceMap.record!(@row, snapshot(repository))
    ResourceMap.record!(other, snapshot(repository))

    assert_equal 1, ResourceMap::Resource.where(workspace: @workspace, external_id: "acme/app").count
  end

  private

  def connection(slug)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: slug.humanize, slug: slug)
    integration.integration_environments.create!
  end

  def web = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web", status: "running")

  def deployed(commit, status)
    ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web",
                           status: status, details: { "deployed_commit" => commit })
  end

  def repository = ResourceMap::Found.new(provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/app", name: "acme/app")

  def link(from, to, relation) = ResourceMap::FoundLink.new(from: from.key, to: to.key, relation: relation)

  def snapshot(*resources, links: [], gaps: []) = ResourceMap::Snapshot.new(resources: resources, links: links, gaps: gaps)

  def resource(external_id) = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: external_id)

  def found(kind, id) = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: kind, external_id: id, name: id)
end
