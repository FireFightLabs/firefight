require "test_helper"

class ResourceMap::HostMatcherTest < ActiveSupport::TestCase
  PASSWORD = "hunter2-secret-pw".freeze
  NEON_HOST = "ep-cool-river-123.eu-central-1.aws.neon.tech".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @platform = connection("northflank")
    @databases = connection("neon")
  end

  test "a setting naming a store's exact address is a matched link, a fact naming the setting, kept by the sweep that follows" do
    record_stores(endpoint("app-db", NEON_HOST))
    record_services(web: { "DATABASE_URL" => "postgres://app:#{PASSWORD}@#{NEON_HOST}/app", "PORT" => "3000" })

    match!

    link = ResourceMap::Link.find_by!(from_resource: resource("web"), to_resource: resource("app-db"))
    assert_equal [ ResourceMap::ORIGIN_MATCHED, [ "DATABASE_URL" ], nil ], [ link.origin, link.variables, link.certainty ]
    assert_not link.unconfirmed?
    assert_equal [ "DATABASE_URL on web names the address Neon reports for app-db" ], link.clues
    assert_includes ResourceMap::Link.facts, link
    assert_match(/DATABASE_URL on web names this address/, link.removal_blocked_reason)

    record_services(web: { "DATABASE_URL" => "postgres://app:#{PASSWORD}@#{NEON_HOST}/app" })
    record_stores(endpoint("app-db", NEON_HOST))
    match!
    assert_equal link.id, ResourceMap::Link.find_by!(from_resource: resource("web"), origin: ResourceMap::ORIGIN_MATCHED).id
  end

  test "a port that differs is another address, and a setting that stops naming the store takes its link away" do
    record_stores(endpoint("app-db", NEON_HOST))
    record_services(web: { "DATABASE_URL" => "postgres://app:#{PASSWORD}@#{NEON_HOST}:6543/app" })

    match!
    assert_not ResourceMap::Link.exists?(from_resource: resource("web"), to_resource: resource("app-db"))

    record_services(web: { "DATABASE_URL" => "postgres://app:#{PASSWORD}@#{NEON_HOST}/app" })
    match!
    assert ResourceMap::Link.exists?(from_resource: resource("web"), origin: ResourceMap::ORIGIN_MATCHED)

    record_services(web: { "DATABASE_URL" => "postgres://app:#{PASSWORD}@elsewhere.example.com/app" })
    match!
    assert_not ResourceMap::Link.exists?(from_resource: resource("web"), origin: ResourceMap::ORIGIN_MATCHED)
  end

  test "an address two stores report is a possible suggestion for each, never a fact" do
    record_stores(endpoint("primary", "db.shared.example.com"), endpoint("standby", "db.shared.example.com"))
    record_services(web: { "DATABASE_URL" => "postgres://app:#{PASSWORD}@db.shared.example.com/app" })

    match!

    links = ResourceMap::Link.where(from_resource: resource("web")).order(:created_at)
    assert_equal [ ResourceMap::ORIGIN_INFERRED ], links.map(&:origin).uniq
    assert_equal [ ResourceMap::CERTAINTY_POSSIBLE ], links.map(&:certainty).uniq
    assert_equal %w[primary standby], links.map { |link| link.to_resource.name }.sort
    assert links.all? { |link| link.variables == [ "DATABASE_URL" ] && link.unconfirmed? }
  end

  test "a host many accounts share is told apart by the database's name, which is only a likely suggestion" do
    host = "aws.connect.psdb.cloud"
    record_stores(endpoint("shop", host, port: 3306, database: "shop", shared: true), endpoint("blog", host, port: 3306, database: "blog", shared: true))
    record_services(web: { "DATABASE_URL" => "mysql2://abc:#{PASSWORD}@#{host}/shop?ssl={}" })

    match!

    link = ResourceMap::Link.find_by!(from_resource: resource("web"))
    assert_equal [ "shop", ResourceMap::ORIGIN_INFERRED, ResourceMap::CERTAINTY_LIKELY ], [ link.to_resource.name, link.origin, link.certainty ]
    assert_match(/shared host/, link.clues.join)
  end

  test "a server holding several databases is told apart by the database's name, which on the account's own server is a fact" do
    host = "acme.database.windows.net"
    record_stores(endpoint("orders", host, port: 1433, database: "orders"), endpoint("billing", host, port: 1433, database: "billing"))
    record_services(web: { "SQL" => "Server=tcp:#{host},1433;Initial Catalog=orders;User ID=app;Password=#{PASSWORD}" })

    match!

    link = ResourceMap::Link.find_by!(from_resource: resource("web"))
    assert_equal [ "orders", ResourceMap::ORIGIN_MATCHED ], [ link.to_resource.name, link.origin ]
  end

  test "a pooler whose hosts are numbered per cluster is matched by its domain and the tenant in the user's name" do
    found = ResourceMap::Endpoint.within(resource: store_key("abcdefghijklmnop"), domain: "pooler.supabase.com", port: 6543, workspace: @workspace,
                                         tenant: "abcdefghijklmnop")
    record_stores(found, names: [ "abcdefghijklmnop", "other" ])
    record_services(web: { "DATABASE_URL" => "postgres://postgres.abcdefghijklmnop:#{PASSWORD}@aws-1-eu-central-1.pooler.supabase.com:6543/postgres" },
                    worker: { "DATABASE_URL" => "postgres://postgres.zzzz:#{PASSWORD}@aws-1-eu-central-1.pooler.supabase.com:6543/postgres" })

    match!

    assert_equal ResourceMap::ORIGIN_MATCHED, ResourceMap::Link.find_by!(from_resource: resource("web")).origin
    assert_not ResourceMap::Link.exists?(from_resource: resource("worker"))
    assert_nil ResourceMap::Endpoint.within(resource: store_key("x"), domain: "pooler.supabase.com", port: 6543, workspace: @workspace)
  end

  test "a reference both sides name exactly, such as a secret's ARN, is a fact" do
    arn = "arn:aws:secretsmanager:eu-west-1:123:secret:rds!db-1"
    record_stores(ResourceMap::Endpoint.reference(resource: store_key("orders"), reference: arn, workspace: @workspace), names: [ "orders" ])
    found = ResourceMap::Use.reference(from: service_key("web"), variable: "DATABASE_PASSWORD", reference: arn, workspace: @workspace)
    ResourceMap.record!(@platform, ResourceMap::Snapshot.new(resources: [ service("web") ], uses: [ found ]))

    match!

    assert_equal [ "DATABASE_PASSWORD" ], ResourceMap::Link.find_by!(from_resource: resource("web"), origin: ResourceMap::ORIGIN_MATCHED).variables
  end

  test "a dismissed pair is never linked again, and an open suggestion for a pair that now matches becomes the fact in place" do
    record_stores(endpoint("app-db", NEON_HOST), endpoint("billing", "billing.example.com"))
    record_services(web: { "DATABASE_URL" => "postgres://app:#{PASSWORD}@#{NEON_HOST}/app", "BILLING_URL" => "postgres://u:p@billing.example.com/b" })
    dismissed = suggestion("web", "app-db").tap(&:dismiss!)
    open = suggestion("web", "billing")

    match!

    assert dismissed.reload.dismissed_at
    assert_equal ResourceMap::ORIGIN_INFERRED, dismissed.origin
    assert_equal 1, ResourceMap::Link.where(from_resource: resource("web"), to_resource: resource("app-db")).count
    assert_equal [ ResourceMap::ORIGIN_MATCHED, nil, [ "BILLING_URL" ] ], open.reload.then { |link| [ link.origin, link.certainty, link.variables ] }
  end

  test "a link a person added stays theirs" do
    record_stores(endpoint("app-db", NEON_HOST))
    record_services(web: { "DATABASE_URL" => "postgres://app:#{PASSWORD}@#{NEON_HOST}/app" })
    added = ResourceMap::Link.add_by_person!(from: resource("web"), to: resource("app-db"), relation: ResourceMap::RELATION_USES, note: "", by: nil)

    match!

    assert_equal [ ResourceMap::ORIGIN_PERSON, [] ], added.reload.then { |link| [ link.origin, link.variables ] }
  end

  test "nothing a sweep keeps holds a setting's value or its password" do
    url = "postgres://app:#{PASSWORD}@#{NEON_HOST}/app"
    record_stores(endpoint("app-db", NEON_HOST))
    snapshot = record_services(web: { "DATABASE_URL" => url, "REDIS_HOST" => "cache.internal", "REDIS_PORT" => "6380" })
    match!

    assert_no_setting_values(snapshot, PASSWORD, NEON_HOST, "cache.internal", url)
    assert ResourceMap::Use.exists?(variable: "REDIS_HOST", port: 6380)
  end

  test "the same address digests differently in another workspace" do
    one = ResourceMap::Fingerprint.of(NEON_HOST, 5432, @workspace)
    assert_equal one, ResourceMap::Fingerprint.of(NEON_HOST.upcase + ".", 5432, @workspace.id)
    assert_not_equal one, ResourceMap::Fingerprint.of(NEON_HOST, 5432, workspaces(:slack_workspace_two))
    assert_not_equal one, ResourceMap::Fingerprint.of(NEON_HOST, 5433, @workspace)
  end

  test "a partial read keeps the settings it did not see, a complete one takes them away" do
    record_services(web: { "DATABASE_URL" => "postgres://u:p@one.example.com/app", "CACHE_URL" => "redis://cache.example.com" })
    gap = ResourceMap::Gap.new(text: "Settings for web could not be read.", kinds: [], settings: true)

    ResourceMap.record!(@platform, ResourceMap::Snapshot.new(resources: [ service("web") ], gaps: [ gap ],
                                                             uses: settings("web", "DATABASE_URL" => "postgres://u:p@one.example.com/app")))
    assert_equal %w[CACHE_URL DATABASE_URL], ResourceMap::Use.where(resource: resource("web")).pluck(:variable).sort

    record_services(web: { "DATABASE_URL" => "postgres://u:p@one.example.com/app" })
    assert_equal %w[DATABASE_URL], ResourceMap::Use.where(resource: resource("web")).pluck(:variable)
  end

  test "a re-read after a change event replaces the settings of what it read and leaves the rest" do
    record_services(web: { "DATABASE_URL" => "postgres://u:p@one.example.com/app" }, worker: { "QUEUE_URL" => "redis://queue.example.com" })
    record_stores(endpoint("app-db", "two.example.com"))

    partial = ResourceMap::Snapshot.new(resources: [ service("web") ], uses: settings("web", "DATABASE_URL" => "postgres://u:p@two.example.com/app"))
    changed = ResourceMap.apply!(@platform, partial, scope: ResourceMap::Scope.new(kind: ResourceMap::KIND_SERVICE, external_id: "web"), at: Time.current)
    Integrations::MapSweep.written!(@platform, changed)

    assert_equal 1, ResourceMap::Use.where(resource: resource("web")).count
    assert_equal [ "QUEUE_URL" ], ResourceMap::Use.where(resource: resource("worker")).pluck(:variable)
    assert ResourceMap::Link.exists?(from_resource: resource("web"), to_resource: resource("app-db"), origin: ResourceMap::ORIGIN_MATCHED)
  end

  test "a declared link carries the settings the provider says it comes from" do
    record_stores(endpoint("app-db", NEON_HOST))
    ResourceMap.record!(@platform, ResourceMap::Snapshot.new(resources: [ service("web") ],
                                                             links: [ ResourceMap::FoundLink.new(from: service_key("web"), to: store_key("app-db"),
                                                                                                 relation: ResourceMap::RELATION_USES, variables: [ "DATABASE_URL" ]) ]))

    assert_equal [ "DATABASE_URL" ], ResourceMap::Link.find_by!(from_resource: resource("web"), origin: ResourceMap::ORIGIN_DECLARED).variables
  end

  private

  def match! = ResourceMap::Matcher.new(@workspace).run!

  def connection(provider)
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: provider.humanize, slug: provider).integration_environments.create!
  end

  def service_key(name) = service(name).key

  def service(name) = ResourceMap::Found.new(provider: "northflank", account: "team/shop", kind: ResourceMap::KIND_SERVICE, external_id: name, name: name)

  def store_key(name) = store(name).key

  def store(name) = ResourceMap::Found.new(provider: "neon", account: "org", kind: ResourceMap::KIND_DATABASE, external_id: name, name: name)

  def endpoint(name, host, port: 5432, database: nil, shared: false)
    ResourceMap::Endpoint.at(resource: store_key(name), host: host, port: port, workspace: @workspace, database: database, shared: shared)
  end

  def record_stores(*endpoints, names: endpoints.map { |found| found.resource.last }.uniq)
    ResourceMap.record!(@databases, ResourceMap::Snapshot.new(resources: names.map { |name| store(name) }, endpoints: endpoints))
  end

  def settings(name, values) = ResourceMap::Use.read(from: service_key(name), workspace: @workspace, values: values)

  def record_services(services)
    snapshot = ResourceMap::Snapshot.new(resources: services.keys.map { |name| service(name.to_s) },
                                         uses: services.flat_map { |name, values| settings(name.to_s, values) })
    ResourceMap.record!(@platform, snapshot)
    snapshot
  end

  def resource(name) = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: name)

  def suggestion(from, to)
    ResourceMap::Link.create!(workspace: @workspace, from_resource: resource(from), to_resource: resource(to), relation: ResourceMap::RELATION_USES,
                              origin: ResourceMap::ORIGIN_INFERRED, certainty: ResourceMap::CERTAINTY_POSSIBLE, last_seen_at: Time.current)
  end
end
