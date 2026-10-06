require "test_helper"

class ResourceMap::MatcherTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    northflank = connection("northflank")
    planetscale = connection("planetscale")
    ResourceMap.record!(northflank, snapshot([ service("web"), service("job"), service("dev-web") ]))
    ResourceMap.record!(planetscale, snapshot([ database("firefight-prod"), branch("firefight-prod"), database("firefight-dev"), branch("firefight-dev") ],
                                              links: [ branch_of("firefight-prod"), branch_of("firefight-dev") ]))
  end

  test "a service uses the database named for its project in its environment, through the production branch" do
    ResourceMap::Matcher.new(@workspace).run!

    assert_equal [ [ "dev-web", "firefight-dev/main" ], [ "job", "firefight-prod/main" ], [ "web", "firefight-prod/main" ] ], suggested.sort
    web = link("web")
    assert_equal ResourceMap::CERTAINTY_LIKELY, web.certainty
    assert web.unconfirmed?
    assert_equal [ "Both are named for firefight", "web names no environment, so Firefight assumes production, like firefight-prod" ], web.clues
    assert_equal [ "Both are named for firefight", "Both are development" ], link("dev-web").clues
  end

  test "a database with no environment in its name is only a possible match" do
    planetscale = connection("planetscale_two")
    ResourceMap.record!(planetscale, snapshot([ database("firefight-analytics") ]))

    ResourceMap::Matcher.new(@workspace).run!

    analytics = ResourceMap::Link.find_by!(to_resource: resource("firefight-analytics"), from_resource: resource("web"))
    assert_equal ResourceMap::CERTAINTY_POSSIBLE, analytics.certainty
    assert_equal [ "Both are named for firefight" ], analytics.clues
  end

  test "sharing only an environment word is not a shared name" do
    ResourceMap.record!(connection("planetscale_three"), snapshot([ database("billing-dev") ]))

    ResourceMap::Matcher.new(@workspace).run!

    assert_not ResourceMap::Link.exists?(to_resource: resource("billing-dev"))
  end

  test "a confirmed or dismissed suggestion stays as it was left, and a link a person added is not suggested again" do
    ResourceMap::Matcher.new(@workspace).run!
    link("web").confirm!(by: nil)
    link("job").dismiss!
    ResourceMap::Link.find_by!(from_resource: resource("dev-web")).destroy!
    ResourceMap::Link.add_by_person!(from: resource("dev-web"), to: resource("firefight-dev/main"), relation: ResourceMap::RELATION_USES, note: "", by: nil)

    ResourceMap::Matcher.new(@workspace).run!

    assert link("web").confirmed_at
    assert link("job").dismissed_at
    assert_equal [ ResourceMap::ORIGIN_PERSON ], ResourceMap::Link.where(from_resource: resource("dev-web")).pluck(:origin)
  end

  test "an open suggestion keeps its id from one sweep to the next, and goes once the map no longer supports it" do
    ResourceMap::Matcher.new(@workspace).run!
    first = link("web").id

    ResourceMap::Matcher.new(@workspace).run!
    assert_equal first, link("web").id

    ResourceMap.record!(ResourceMap::Resource.find_by!(external_id: "web").integration_environment, snapshot([ service("job"), service("dev-web") ]))
    ResourceMap::Matcher.new(@workspace).run!
    assert_not ResourceMap::Link.exists?(first)
  end

  test "what stops if a resource fails counts facts only, and keeps what the suggestions would add apart" do
    ResourceMap::Matcher.new(@workspace).run!
    link("web").confirm!(by: nil)

    row = ResourceMap::View.new(@workspace, map_reader).rows.find { |each| each.resource.external_id == "firefight-prod/main" }

    assert_equal [ resource("web").id ], row.dependent_ids
    assert_equal [ resource("job").id ], row.suggested_dependent_ids
  end

  test "a setting named for a store's provider with its value hidden is a possible suggestion when one database fits" do
    neon = connection("neon")
    ResourceMap.record!(neon, snapshot([ neon_database("ledger") ]))
    record_settings("job", names: [ "NEON_DATABASE_URL" ])

    ResourceMap::Matcher.new(@workspace).run!

    link = ResourceMap::Link.find_by!(from_resource: resource("job"), to_resource: resource("ledger"))
    assert_equal [ ResourceMap::CERTAINTY_POSSIBLE, [ "NEON_DATABASE_URL" ] ], [ link.certainty, link.variables ]
    assert_equal [ "job has a setting called NEON_DATABASE_URL, which points at Neon" ], link.clues
  end

  test "a setting's name that agrees with a shared project word makes the suggestion likely, and two databases it could be make none alone" do
    neon = connection("neon")
    ResourceMap.record!(neon, snapshot([ neon_database("firefight-analytics"), neon_database("ledger") ]))
    record_settings("web", names: [ "NEON_URL" ])

    ResourceMap::Matcher.new(@workspace).run!

    link = ResourceMap::Link.find_by!(from_resource: resource("web"), to_resource: resource("firefight-analytics"))
    assert_equal ResourceMap::CERTAINTY_LIKELY, link.certainty
    assert_equal [ "Both are named for firefight", "web has a setting called NEON_URL, which points at Neon" ], link.clues
    assert_not ResourceMap::Link.exists?(from_resource: resource("web"), to_resource: resource("ledger"))
  end

  test "a setting named for an engine fits the database that reports it" do
    upstash = connection("upstash")
    ResourceMap.record!(upstash, ResourceMap::Snapshot.new(resources: [
                          ResourceMap::Found.new(provider: "upstash", account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: "sessions",
                                                 name: "sessions", details: { "engine" => "redis" })
                        ]))
    record_settings("job", names: [ "REDIS_URL" ])

    ResourceMap::Matcher.new(@workspace).run!

    assert_equal [ "job has a setting called REDIS_URL, which points at a Redis store" ],
                 ResourceMap::Link.find_by!(from_resource: resource("job"), to_resource: resource("sessions")).clues
  end

  test "an exact match and the suggestions are written under the one per-workspace lock" do
    held = nil
    ResourceMap::HostMatcher.any_instance.stubs(:run!).with do
      held = ResourceMap::Link.connection.select_value("SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()")
      true
    end.returns([])

    ResourceMap::Matcher.new(@workspace).run!

    assert_equal 1, held
  end

  private

  def record_settings(name, names:)
    row = ResourceMap::Resource.find_by!(external_id: name).integration_environment
    found = ResourceMap::Use.read(from: service(name).key, workspace: @workspace, names: names)
    ResourceMap.record!(row, snapshot(ResourceMap::Resource.where(integration_environment: row).map { |each| service(each.external_id) }).with(uses: found))
  end

  def neon_database(name) = ResourceMap::Found.new(provider: "neon", account: "org", kind: ResourceMap::KIND_DATABASE, external_id: name, name: name)

  def connection(slug)
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: slug.humanize, slug: slug).integration_environments.create!
  end

  def snapshot(resources, links: []) = ResourceMap::Snapshot.new(resources: resources, links: links)

  def service(name) = ResourceMap::Found.new(provider: "northflank", account: "team/firefight", kind: ResourceMap::KIND_SERVICE, external_id: name, name: name)

  def database(name) = ResourceMap::Found.new(provider: "planetscale", account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: name, name: name)

  def branch(database)
    ResourceMap::Found.new(provider: "planetscale", account: "acme", kind: ResourceMap::KIND_BRANCH, external_id: "#{database}/main",
                           name: "#{database}/main", details: { ResourceMap::PRODUCTION => true })
  end

  def branch_of(name) = ResourceMap::FoundLink.new(from: branch(name).key, to: database(name).key, relation: ResourceMap::RELATION_BRANCH_OF)

  def resource(id) = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: id)

  def link(from) = ResourceMap::Link.find_by!(workspace: @workspace, from_resource: resource(from), origin: ResourceMap::ORIGIN_INFERRED)

  def suggested
    ResourceMap::Link.where(workspace: @workspace, origin: ResourceMap::ORIGIN_INFERRED).includes(:from_resource, :to_resource)
                     .map { |each| [ each.from_resource.name, each.to_resource.name ] }
  end
end
