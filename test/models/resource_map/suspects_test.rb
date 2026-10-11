require "test_helper"

# Before Halon's first model call on something failing, Firefight's own code lists what changed on it and its neighbours
# up to two hops, and the alerts on them, nearest to when the trouble began first, as candidates and never a cause.
class ResourceMap::SuspectsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!
    @api = make("api")
    @worker = make("worker")
    @orders = make("orders", kind: ResourceMap::KIND_DATABASE)
    @far = make("billing")
    @unrelated = make("marketing")
    link(@api, @orders)
    link(@worker, @orders)
    link(@far, @worker)
    @began = 20.minutes.ago
  end

  test "changes on what fails and its neighbours up to two hops are listed nearest to when it began first, with how far each is" do
    deployed!(@worker, at: @began - 2.minutes)
    deployed!(@api, at: @began - 90.minutes)
    deployed!(@unrelated, at: @began - 1.minute)
    deployed!(@far, at: @began - 3.minutes)

    suspects = ResourceMap::Suspects.new(workspace: @workspace, principal: @admin, roots: [ @api ], anchor: @began, from: @began - 2.hours)

    assert_equal %w[worker api], suspects.list.map(&:where)
    assert_equal [ 2, 0 ], suspects.list.map(&:hop)
    assert suspects.text.start_with?(ResourceMap::Suspects::LEAD_WORDS)
    assert_match "2 hops from what is failing", suspects.text
    assert_no_match(/marketing|billing/, suspects.text)
  end

  test "an alert naming one of them is a suspect too, and nothing changed means no list at all" do
    source = @workspace.alert_sources.create!(name: "Datadog", provider: AlertSource::PROVIDER_MIXPANEL)
    source.alerts.create!(workspace: @workspace, external_id: "a1", fingerprint: "f1", fields: { "title" => "orders connections at limit" },
                          received_at: @began + 1.minute, last_seen_at: @began + 1.minute)

    suspects = ResourceMap::Suspects.new(workspace: @workspace, principal: @admin, roots: [ @api ], anchor: @began, from: @began - 2.hours)
    assert_equal [ "Alert: orders connections at limit" ], suspects.list.map(&:what)

    quiet = ResourceMap::Suspects.new(workspace: @workspace, principal: @admin, roots: [ @unrelated ], anchor: @began, from: @began - 2.hours)
    assert_nil quiet.text
  end

  test "a chat's turn is told the list when the person names something on the map, never for a plain question, and never twice" do
    deployed!(@worker, at: 5.minutes.ago)
    conversation = Conversation.start_personal!(workspace: @workspace, member: @admin)
    turn = Conversation::Turn.new(conversation, asker: @admin)

    assert_nil Conversation::Suspects.note(turn, "how do I invite someone?")
    note = Conversation::Suspects.note(turn, "orders is refusing connections")
    assert_match "worker", note
    conversation.chat_record.nudge!(note)
    assert_nil Conversation::Suspects.note(turn, "orders is refusing connections"), "the same list is not told again"
  end

  private

  def make(name, kind: ResourceMap::KIND_SERVICE)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "acme", kind: kind, external_id: name, name: name,
                                  status: "running", integration_environment: @row, first_seen_at: 1.day.ago, last_seen_at: 1.hour.ago)
  end

  def link(from, to)
    ResourceMap::Link.create!(workspace: @workspace, from_resource: from, to_resource: to, relation: ResourceMap::RELATION_USES,
                              origin: ResourceMap::ORIGIN_DECLARED, last_seen_at: Time.current)
  end

  def deployed!(resource, at:)
    resource.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, from_value: "a1", to_value: "b2", happened_at: at)
  end
end
