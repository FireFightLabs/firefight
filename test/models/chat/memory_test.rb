require "test_helper"

class Chat::MemoryTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @checkout = catalog_entries(:auth_service)
  end

  test "a chat or run starts with the memories about what it touches and the workspace wide ones, confirmed first, never disputed or rejected ones" do
    confirmed = remember("Auth Service runs on web", subject: @checkout, state: Chat::Memory::STATE_CONFIRMED)
    workspace_wide = remember("Deploys happen from main")
    remember("Something unrelated", subject: catalog_entries(:platform_team))
    remember("Auth Service uses Redis", subject: @checkout, state: Chat::Memory::STATE_REJECTED)
    remember("Auth Service is in Frankfurt", subject: @checkout, state: Chat::Memory::STATE_DISPUTED)
    remember("Auth Service retries twice", subject: @checkout, state: Chat::Memory::STATE_EXPIRED)

    assert_equal [ confirmed, workspace_wide ], Chat::Memory.starting_with(@workspace, [ @checkout ])
  end

  test "an incident touches the catalog services named on it and the resources they run on" do
    web = map_resource("web")
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: @checkout, resource: web)
    incident = incidents(:active_critical_ws1)
    IncidentFieldValue.create!(incident: incident, incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: @checkout)

    assert_equal [ @checkout, web ], Chat::Memory.subjects_for(incident)
  end

  test "memories handed to a chat or run count as used once for it, however often it starts a turn" do
    memory = remember("Deploys happen from main")
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    other = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))

    3.times { Chat::Memory.handed_to!([ memory ], conversation) }
    Chat::Memory.handed_to!([ memory ], other)

    assert_equal 2, memory.reload.use_count
    assert memory.last_used_at
  end

  test "recall matches by subject and by any word asked, and a dispute is decided once" do
    production = remember("firefight-prod is the production database", subject: @checkout)
    remember("Deploys happen from main")

    assert_equal [ production ], Chat::Memory.recall(@workspace, query: "which PRODUCTION database").memories
    assert_equal [ production ], Chat::Memory.recall(@workspace, subject: @checkout).memories
    assert production.dispute!("The query against it found no tables")
    assert_not production.dispute!("again")
    assert_equal "The query against it found no tables", production.reload.state_reason
    assert_empty Chat::Memory.recall(@workspace, subject: @checkout).memories
  end

  test "recall ranks by how many asked words match, stemmed, with the whole phrase first, then confirmed, then newest" do
    one_word = remember("Restarting web clears the cache")
    both = remember("The checkout queue restarts on deploy")
    phrase = remember("A checkout queue restart drops orders")
    confirmed_one = remember("The worker restarts nightly", state: Chat::Memory::STATE_CONFIRMED)
    remember("Nothing to do with it")

    found = Chat::Memory.recall(@workspace, query: "checkout queue restarted").memories

    assert_equal [ phrase, both ], found.first(2)
    assert_equal [ confirmed_one, one_word ], found.last(2)
  end

  test "recall answers with at most twenty and says how many more matched" do
    25.times { |index| remember("Queue #{index} drains into the ledger") }

    recalled = Chat::Memory.recall(@workspace, query: "ledger")

    assert_equal Chat::Memory::STARTING_LIMIT, recalled.memories.size
    assert_equal 5, recalled.more
  end

  test "a reworded fact is known already, a rewording of a rejected one is refused, and a negation is a different fact" do
    known = remember("Checkout uses MySQL for orders", subject: @checkout)
    rejected = remember("The cache is Redis", state: Chat::Memory::STATE_REJECTED)

    assert_equal [ Chat::Memory::LEARNED_KNOWN, known ], learned("for orders, checkout uses mysql.", subject: @checkout).deconstruct.first(2)
    assert_equal [ Chat::Memory::LEARNED_REJECTED, rejected ], learned("Redis is the cache!").deconstruct.first(2)
    assert_equal Chat::Memory::LEARNED_SAVED, learned("Checkout does not use MySQL for orders", subject: @checkout).outcome
    assert_equal Chat::Memory::LEARNED_SAVED, learned("Checkout uses MySQL for orders").outcome, "the same words about something else are a new fact"
  end

  test "an expired memory learned again waits for a person afresh" do
    expired = remember("Deploys happen from main", state: Chat::Memory::STATE_EXPIRED)

    assert_equal [ Chat::Memory::LEARNED_KNOWN, expired ], learned("deploys happen from main").deconstruct.first(2)
    assert_equal Chat::Memory::STATE_UNCONFIRMED, expired.reload.state
  end

  test "live values are never learned, and setup facts with numbers in them are" do
    [
      "p99 latency on checkout is 850ms and the error rate is 4.2%",
      "Checkout currently runs 3 replicas",
      "Deployed on 2026-10-05 at 14:02",
      "The queue is at 1200 rps and 30 errors right now"
    ].each do |text|
      assert_equal Chat::Memory::LEARNED_REFUSED, learned(text).outcome, text
    end

    [
      "Backups run at 02:00 UTC every night",
      "Checkout times out after 30s",
      "The alert fires when the error rate passes 5%",
      "Port 5432 serves the primary on db-1",
      "The pool allows 100 connections",
      "Max connections on the primary is 100",
      "Checkout runs on Postgres 16"
    ].each do |text|
      assert_equal Chat::Memory::LEARNED_SAVED, learned(text).outcome, text
    end
  end

  test "facts about a person are never learned, and a name that is also a word is not read as one" do
    member = workspace_memberships(:alice_workspace_one)
    full_name = member.user.name
    first_name = full_name.split.first

    [
      "Ask ada@example.com before touching billing",
      "<@U12345678> owns the billing service",
      "Billing is owned by #{full_name.downcase}",
      "When billing breaks, page #{first_name}"
    ].each do |text|
      refused = learned(text)
      assert_equal [ Chat::Memory::LEARNED_REFUSED, Chat::Memory::Screening::ABOUT_A_PERSON ], [ refused.outcome, refused.reason ], text
    end
    assert_equal Chat::Memory::LEARNED_SAVED, learned("#{first_name.downcase} is not a person here").outcome
  end

  test "a name nothing has is refused, one several things share lists their ids, and an id picks one" do
    web = map_resource("web")
    other_web = map_resource("web", external_id: "web-eu")

    assert_equal "Nothing called ledger is on the map or in the catalog.", Chat::Memory.subject_named(@workspace, "ledger").refusal
    shared = Chat::Memory.subject_named(@workspace, "web")
    assert_nil shared.subject
    assert_includes shared.refusal, web.id
    assert_includes shared.refusal, other_web.id
    assert_equal other_web, Chat::Memory.subject_named(@workspace, other_web.id).subject
    assert_equal @checkout, Chat::Memory.subject_named(@workspace, @checkout.slug).subject
  end

  test "a resource gone from the map is found by name only when asked for, and only when nothing present has the name" do
    gone = map_resource("ledger")
    gone.update!(removed_at: 1.day.ago)

    assert Chat::Memory.subject_named(@workspace, "ledger").refusal
    assert_equal gone, Chat::Memory.subject_named(@workspace, "ledger", removed: true).subject
  end

  test "a flag the sweep set for a removed resource is lifted when it comes back, never one a person decided on since" do
    web = map_resource("web")
    lifted = remember("web serves checkout", subject: web, state: Chat::Memory::STATE_CONFIRMED)
    decided = remember("web runs two instances", subject: web)
    renamed = remember("web is behind the CDN", subject: web)

    Chat::Memory.flag_outdated!(web, "web is no longer reported by its connection", cause: Chat::Memory::OUTDATED_REMOVED)
    renamed.update_columns(outdated_cause: Chat::Memory::OUTDATED_RENAMED)
    decided.reload.confirm!(by: workspace_memberships(:alice_workspace_one))
    Chat::Memory.clear_outdated!(web, cause: Chat::Memory::OUTDATED_REMOVED)

    assert_equal [ Chat::Memory::STATE_CONFIRMED, nil, nil ], lifted.reload.values_at(:state, :state_reason, :outdated_cause)
    assert_equal Chat::Memory::STATE_CONFIRMED, decided.reload.state
    assert_equal workspace_memberships(:alice_workspace_one), decided.confirmed_by
    assert_equal Chat::Memory::STATE_OUTDATED, renamed.reload.state
  end

  test "a workspace that chose a window stops using what nobody confirmed in it, and one that did not keeps using it" do
    old = remember("Deploys happen from main")
    old.update_columns(updated_at: 31.days.ago)
    fresh = remember("Checkout retries twice")
    confirmed = remember("Checkout runs in Frankfurt", state: Chat::Memory::STATE_CONFIRMED)
    confirmed.update_columns(updated_at: 90.days.ago)

    assert_equal 0, Chat::Memory.expire!(@workspace)
    @workspace.update!(memory_expiry_days: 30)
    assert_equal 1, Chat::Memory.expire!(@workspace)

    assert_equal [ Chat::Memory::STATE_EXPIRED, "Nobody confirmed it within 30 days." ], old.reload.values_at(:state, :state_reason)
    assert_equal Chat::Memory::STATE_UNCONFIRMED, fresh.reload.state
    assert_equal Chat::Memory::STATE_CONFIRMED, confirmed.reload.state
    assert_nil old.confirm_blocked_reason, "a person can still confirm an expired memory"
  end

  test "Halon reads a postmortem's confirmation as a postmortem's, and a person's as theirs" do
    member = workspace_memberships(:alice_workspace_one)
    postmortem = Postmortem.create!(incident: incidents(:active_critical_ws1), generated_by: member, title: "Pool", status: Postmortem::STATUS_COMPLETED,
                                    content: { "html" => "<p>It was the pool</p>" })
    nobody = remember("The pool is 20")
    someone = remember("The pool is shared")

    nobody.confirm_from_postmortem!(postmortem, by: nil)
    someone.confirm_from_postmortem!(postmortem, by: member)

    assert_includes nobody.line, "confirmed by a postmortem"
    assert_includes someone.line, "confirmed by #{member.display_name}"
  end

  private

  def remember(text, subject: nil, state: Chat::Memory::STATE_UNCONFIRMED)
    Chat::Memory.create!(workspace: @workspace, text: text, subject: subject, state: state)
  end

  def learned(text, subject: nil) = Chat::Memory.learn!(@workspace, text: text, subject: subject, source: nil)

  def map_resource(name, external_id: name)
    integration = @workspace.integrations.find_by(slug: "northflank") ||
                  @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    environment = integration.integration_environments.first || integration.integration_environments.create!
    ResourceMap::Resource.create!(workspace: @workspace, integration_environment: environment, provider: "northflank", account: "acme/shop",
                                  kind: ResourceMap::KIND_SERVICE, external_id: external_id, name: name, first_seen_at: Time.current, last_seen_at: Time.current)
  end
end
