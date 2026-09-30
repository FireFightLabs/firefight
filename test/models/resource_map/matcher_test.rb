require "test_helper"

class ResourceMap::MatcherTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    northflank = connection("northflank")
    planetscale = connection("planetscale")
    ResourceMap.record!(northflank, snapshot([ service("web"), service("job"), service("dev-web") ]))
    ResourceMap.record!(planetscale, snapshot([ database("firefight-prod"), branch("firefight-prod"), database("firefight-dev"), branch("firefight-dev") ]))
  end

  test "a service uses the database named for its project in its environment, through the production branch" do
    ResourceMap::Matcher.new(@workspace).run!

    assert_equal [ [ "dev-web", "firefight-dev/main" ], [ "job", "firefight-prod/main" ], [ "web", "firefight-prod/main" ] ], suggested.sort
    web = link("web")
    assert_equal ResourceMap::CERTAINTY_LIKELY, web.certainty
    assert web.unconfirmed?
    assert_equal [ "Both are named for firefight", "web has no environment in its name, so it is taken as production, like firefight-prod" ], web.clues
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

  test "what stops if a resource fails counts facts only, and keeps what the suggestions would add apart" do
    ResourceMap::Matcher.new(@workspace).run!
    link("web").confirm!(by: nil)

    row = ResourceMap::View.new(@workspace).rows.find { |each| each.resource.external_id == "firefight-prod/main" }

    assert_equal [ resource("web").id ], row.dependent_ids
    assert_equal [ resource("job").id ], row.suggested_dependent_ids
  end

  private

  def connection(slug)
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: slug.humanize, slug: slug).integration_environments.create!
  end

  def snapshot(resources) = ResourceMap::Snapshot.new(resources: resources)

  def service(name) = ResourceMap::Found.new(provider: "northflank", account: "team/firefight", kind: ResourceMap::KIND_SERVICE, external_id: name, name: name)

  def database(name) = ResourceMap::Found.new(provider: "planetscale", account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: name, name: name)

  def branch(database)
    ResourceMap::Found.new(provider: "planetscale", account: "acme", kind: ResourceMap::KIND_BRANCH, external_id: "#{database}/main",
                           name: "#{database}/main", details: { "production" => true })
  end

  def resource(id) = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: id)

  def link(from) = ResourceMap::Link.find_by!(workspace: @workspace, from_resource: resource(from), origin: ResourceMap::ORIGIN_INFERRED)

  def suggested
    ResourceMap::Link.where(workspace: @workspace, origin: ResourceMap::ORIGIN_INFERRED).includes(:from_resource, :to_resource)
                     .map { |each| [ each.from_resource.name, each.to_resource.name ] }
  end
end
