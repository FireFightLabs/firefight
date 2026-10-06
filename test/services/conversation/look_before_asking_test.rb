require "test_helper"

# Seen in a real chat, a person pasted Resend's DNS setup guide, which tells an assistant to ask which DNS provider they
# use first. Halon asked, though the domain was a zone in the workspace's Cloudflare account on the map, and once told,
# found the zone with Cloudflare's execute, which asks the person to confirm every call.
class Conversation::LookBeforeAskingTest < ActiveSupport::TestCase
  PASTED = "Please first ask me which DNS provider I use, then give me step-by-step instructions to add the DNS " \
           "records Resend needs to verify faylee.app.".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @asker = workspace_memberships(:alice_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                  settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    row = integration.integration_environments.create!
    %w[search docs].each { |name| tool!(integration, name, read_only: true) }
    tool!(integration, "execute", read_only: false)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "cloudflare", account: "Faylee", kind: ResourceMap::KIND_ZONE,
                                  external_id: "zone-faylee", name: "faylee.app", url: "https://dash.cloudflare.com/acc123/faylee.app",
                                  integration_environment: row, first_seen_at: Time.current, last_seen_at: Time.current)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @asker)
  end

  test "a pasted guide that says to ask first is answered from the map, without asking and without a tool that confirms" do
    instructions, tools = answer(PASTED)

    assert_includes instructions, FirefightAi::LookFirstRule::RULE
    assert_includes instructions, FirefightAi::LookFirstRule::MAP_RULE
    assert_match "says to ask them first, since asking them to confirm what you found answers it", FirefightAi::LookFirstRule::RULE
    assert_match "look it up on the resource map first. get_resource_map reads the map", FirefightAi::LookFirstRule::MAP_RULE

    turn = Conversation::Turn.new(@conversation, asker: @asker)
    map = Chat::Tools.catalog(turn).find { |entry| entry.name == Mcp::Tools::GET_RESOURCE_MAP }
    assert_equal Chat::Tools::STATE_READY, map.state
    assert map.description.start_with?("The first place to find which provider and account hold a named domain, zone, service or database.")

    open_tools = tools.find { |tool| tool.name == Chat::Tools::Open.tool_name }
    assert_match "The resource map: read off the connections, for where something runs and which provider and account hold it",
                 open_tools.description

    use_skill = tools.find { |tool| tool.name == Chat::Tools::UseSkill.tool_name }
    steps = use_skill.call("skill" => "cloudflare_dns")
    assert steps.start_with?("Start from the zone on the resource map. `get_resource_map` with the domain")
    offered_map = @offered.flatten.find { |tool| tool.name == Mcp::Tools::GET_RESOURCE_MAP }
    assert offered_map, "loading the DNS skill hands over the map"
    assert_not offered_map.requires_approval?
    status = @offered.flatten.find { |tool| tool.name == "resource_status" }
    assert status, "loading the DNS skill hands over the zone's status, for whoever cannot read the whole map"
    assert_not status.requires_approval?

    said = offered_map.call(resource: "faylee.app")
    assert_match "\"provider\": \"cloudflare\"", said
    assert_match "\"id\": \"zone-faylee\"", said
  end

  private

  def tool!(integration, name, read_only:)
    tool = integration.tools.create!(name: name, description: name, read_only: read_only, enabled: true, params_schema: { "type" => "object" })
    Ability::Grant.create!(workspace: @workspace, principal: @asker, action: tool.reload.ability_action)
  end

  # The real prompt, with the loop stubbed, so what the model would be told and handed is what is checked.
  def answer(question)
    instructions = nil
    tools = nil
    @offered = []
    Chat.any_instance.stubs(:with_instructions).with { |text| instructions = text }
    Chat.any_instance.stubs(:with_caching)
    Chat.any_instance.stubs(:with_tools).with { |*given| tools ? @offered << given : tools = given }
    outcome = FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_ANSWERED, turns_used: 1, spent_micros: 0)
    FirefightAi::AgentLoop.stubs(:new).returns(stub(run: outcome))
    @conversation.ask!(question)
    Conversation::Runner.new(@conversation, asker: @asker).run
    [ instructions, tools ]
  end
end
