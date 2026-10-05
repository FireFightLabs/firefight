require "test_helper"

class ResourceMap::GraphTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "dependents are found against the links and what a resource depends on along them, each at its nearest hop" do
    domain, web, database = make("shop.example.com", ResourceMap::KIND_DOMAIN), make("web"), make("orders", ResourceMap::KIND_DATABASE)
    link(domain, web, ResourceMap::RELATION_SERVED_BY)
    link(web, database)

    assert_equal [ [ "web", 1 ], [ "shop.example.com", 2 ] ], walked(database)
    assert_equal [ [ "web", 1 ], [ "orders", 2 ] ], walked(domain, direction: ResourceMap::Graph::DEPENDS_ON)
    assert_equal [ [ "shop.example.com", 2 ] ], walked(database, kinds: [ ResourceMap::KIND_DOMAIN ])
  end

  test "a cycle ends the walk rather than going round it, and the root is never its own dependent" do
    a, b, c = make("a"), make("b"), make("c")
    link(a, b)
    link(b, c)
    link(c, a)

    assert_equal [ [ "b", 1 ], [ "a", 2 ] ], walked(c)
    assert_equal 2, ResourceMap::Graph.new(c).total
  end

  test "the hop limit and the node limit stop the walk, and the node limit says how many were left out" do
    chain = %w[a b c d e].map { |name| make(name) }
    chain.each_cons(2) { |from, to| link(from, to) }

    assert_equal [ [ "d", 1 ], [ "c", 2 ] ], walked(chain.last, hops: 2)
    graph = ResourceMap::Graph.new(chain.last, limit: 3)
    assert_equal [ %w[d c b], 4, 1 ], [ graph.nodes.map { |node| node.resource.name }, graph.total, graph.truncated ]
  end

  test "a repository a resource is managed in is reached but never walked past" do
    repository, web, other = make("acme/infra", ResourceMap::KIND_REPOSITORY), make("web"), make("other")
    link(web, repository, ResourceMap::RELATION_MANAGED_BY)
    link(other, repository, ResourceMap::RELATION_MANAGED_BY)
    link(repository, make("ci"), ResourceMap::RELATION_BUILT_FROM)

    assert_empty walked(repository), "managed_by is not a runtime relation"
    everything = ResourceMap::RELATIONS
    assert_equal [ [ "acme/infra", 1 ] ], walked(web, direction: ResourceMap::Graph::DEPENDS_ON, relations: everything)
    assert_equal [ [ "other", 1 ], [ "web", 1 ] ], walked(repository, relations: everything).sort
  end

  test "suggestions are left out unless asked for, dismissed ones always, and removed resources and those outside within are never walked" do
    database, web, guessed, gone, hidden = make("orders"), make("web"), make("worker"), make("old"), make("hidden")
    link(web, database)
    link(guessed, database, origin: ResourceMap::ORIGIN_INFERRED)
    link(make("dismissed"), database, origin: ResourceMap::ORIGIN_SUGGESTED).update!(dismissed_at: Time.current)
    link(gone, database)
    gone.update!(removed_at: Time.current)
    link(hidden, database)
    link(make("behind hidden"), hidden)

    assert_equal %w[behind\ hidden hidden web], walked(database).map(&:first).sort
    assert_equal %w[behind\ hidden hidden web worker], walked(database, suggestions: true).map(&:first).sort
    visible = ResourceMap::Resource.where.not(name: "hidden")
    assert_equal %w[web], walked(database, within: visible).map(&:first)
  end

  test "links are those walked between the root and the nodes shown" do
    database, web = make("orders"), make("web")
    walked_link = link(web, database)
    link(make("guess"), database, origin: ResourceMap::ORIGIN_SUGGESTED)

    assert_equal [ walked_link ], ResourceMap::Graph.new(database).links.to_a
  end

  private

  def make(name, kind = ResourceMap::KIND_SERVICE)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "aws", account: "111", kind: kind, external_id: name, name: name,
                                  first_seen_at: 1.day.ago, last_seen_at: 1.hour.ago)
  end

  def link(from, to, relation = ResourceMap::RELATION_USES, origin: ResourceMap::ORIGIN_DECLARED)
    ResourceMap::Link.create!(workspace: @workspace, from_resource: from, to_resource: to, relation: relation, origin: origin, last_seen_at: Time.current)
  end

  def walked(root, **options) = ResourceMap::Graph.new(root, **options).nodes.map { |node| [ node.resource.name, node.hop ] }
end
