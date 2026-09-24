require "test_helper"

class Mcp::Tools::InvestigationsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    FirefightAi.stubs(:context_window).returns(200_000)
  end

  test "an outside agent can start an investigation on an incident, as whoever its key belongs to" do
    response = Mcp::Tools::StartInvestigation.perform_with_principal(
      workspace: @workspace, principal: @member, args: { incident: @incident.identifier }
    )

    run = @workspace.investigations.sole
    assert_equal run.id, response.structured_content[:id]
    assert_equal Investigation::TRIGGER_MCP, run.trigger_source
    assert_equal @member, run.triggered_by
    assert_enqueued_with(job: InvestigationJob, args: [ run.id ])
  end

  test "an outside agent hands over what it knows, the same fields the chat uses" do
    Mcp::Tools::StartInvestigation.perform_with_principal(
      workspace: @workspace, principal: @member,
      args: { incident: @incident.identifier, symptom: "checkout returns 500", error_text: "PoolExhausted" }
    )

    brief = @workspace.investigations.sole.brief
    assert_equal "PoolExhausted", brief[Investigation::Brief::KEY_ERROR_TEXT]
    assert_equal Investigation::Brief::SOURCE_MCP, brief[Investigation::Brief::KEY_SOURCE]
    assert_equal Investigation::Brief::SCHEMA.keys.map(&:to_s).sort,
                 (Mcp::Tools::StartInvestigation.input_schema_value.to_h[:properties].keys.map(&:to_s) - [ "incident" ]).sort
  end

  test "an outside agent can investigate a problem nobody has declared an incident for, given what is wrong" do
    response = Mcp::Tools::StartInvestigation.perform_with_principal(
      workspace: @workspace, principal: @member, args: { symptom: "checkout is slow" }
    )

    run = @workspace.investigations.find_by!(id: response.structured_content[:id])
    assert_nil run.subject
    assert_equal "checkout is slow", response.structured_content[:question]
  end

  test "with neither an incident nor what is wrong, nothing starts" do
    response = Mcp::Tools::StartInvestigation.perform_with_principal(workspace: @workspace, principal: @member, args: {})

    assert response.error?
    assert_equal 0, @workspace.investigations.count
  end

  test "a second request while one is running is told so rather than starting another" do
    Mcp::Tools::StartInvestigation.perform_with_principal(workspace: @workspace, principal: @member, args: { incident: @incident.identifier })

    response = Mcp::Tools::StartInvestigation.perform_with_principal(workspace: @workspace, principal: @member, args: { incident: @incident.identifier })

    assert response.error?
    assert_match "Already investigating", response.content.first[:text]
    assert_equal 1, @workspace.investigations.count
  end

  test "an incident that is over cannot be investigated, with the reason" do
    response = Mcp::Tools::StartInvestigation.perform_with_principal(
      workspace: @workspace, principal: @member, args: { incident: incidents(:resolved_minor_ws1).identifier }
    )

    assert response.error?
    assert_match "nothing left to investigate", response.content.first[:text]
  end

  test "a workspace without the agent says why" do
    FeatureFlags.disable!(@workspace, FeatureFlags::AI_SRE)

    response = Mcp::Tools::StartInvestigation.perform_with_principal(workspace: @workspace, principal: @member, args: { incident: @incident.identifier })

    assert response.error?
    assert_match "not turned on", response.content.first[:text]
  end

  test "a run is read back whole: theories with their steps, the steps, and the finding with its sources" do
    run = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: @member, max_turns: 10, max_spend_cents: 400
    )
    step = run.steps.create!(
      position: 1, tool_name: "commit_lookup", label: "Commit lookup abc123", action_key: "github.commit_lookup",
      status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current
    )
    run.record_hypothesis!(assertion: "The deploy did it", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])
    run.conclude!(summary: "The 14:02 deploy raised the pool size", hypothesis_assertion: "The deploy did it",
                  evidence: [ { claim: "The commit raised the pool size", steps: [ 1 ] } ], gaps: "logs")
    run.finish!(status: Investigation::STATUS_SUCCEEDED)

    response = Mcp::Tools::GetInvestigation.perform(workspace: @workspace, args: { investigation: run.id })
    body = response.structured_content

    assert_equal Investigation::STATUS_SUCCEEDED, body[:status]
    assert_equal @incident.identifier, body[:incident]
    assert_equal [ [ "The deploy did it", "supported", [ 1 ] ] ], body[:hypotheses].map { |h| [ h[:assertion], h[:status], h[:steps] ] }
    assert_equal [ [ 1, "Commit lookup abc123", "succeeded" ] ], body[:steps].map { |s| [ s[:position], s[:label], s[:status] ] }
    assert_equal "The 14:02 deploy raised the pool size", body.dig(:finding, :summary)
    assert_equal [ { claim: "The commit raised the pool size", steps: [ 1 ], sources: [ "Commit lookup abc123" ] } ], body.dig(:finding, :evidence)
    assert_equal "logs", body.dig(:finding, :gaps)
    assert_nil step.raw_result, "nothing here reads raw output, and the tool must not either"
  end

  test "a run can be found by its incident, newest first" do
    older = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)
    older.finish!(status: Investigation::STATUS_FAILED, error_summary: "x")
    newer = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)

    response = Mcp::Tools::GetInvestigation.perform(workspace: @workspace, args: { incident: @incident.identifier })

    assert_equal newer.id, response.structured_content[:id]
  end

  test "a rehearsal is never read back, by its incident or by its id" do
    real = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)
    rehearsal = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true, max_turns: 10, max_spend_cents: 400
    )

    response = Mcp::Tools::GetInvestigation.perform(workspace: @workspace, args: { incident: @incident.identifier })
    assert_equal real.id, response.structured_content[:id]
    assert_raises(ActiveRecord::RecordNotFound) do
      Mcp::Tools::GetInvestigation.perform(workspace: @workspace, args: { investigation: rehearsal.id })
    end
  end

  test "a run in another workspace is out of reach" do
    other = workspaces(:slack_workspace_two)
    run = other.investigations.create!(subject: other.incidents.first, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)

    assert_raises(ActiveRecord::RecordNotFound) do
      Mcp::Tools::GetInvestigation.perform(workspace: @workspace, args: { investigation: run.id })
    end
  end

  test "a run that stopped says why in plain words and never the technical cause" do
    run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)
    run.finish!(status: Investigation::STATUS_FAILED, error_summary: "ContextLengthExceededError")

    body = Mcp::Tools::GetInvestigation.perform(workspace: @workspace, args: { investigation: run.id }).structured_content

    assert_equal Investigation::STATUS_FAILED, body[:status]
    assert_no_match(/ContextLength/, body.to_json)
  end
end
