require "test_helper"

class Slack::Modals::IncidentUpdateTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :incidents,
           :incident_forms, :incident_form_fields, :incident_field_definitions,
           :catalog_types, :incident_field_options

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "the status select dispatches so the form can follow what is picked" do
    block = status_block(build)

    assert block[:dispatch_action]
    assert_equal Identifiers::INCIDENT_UPDATE_STATUS_SELECT, block.dig(:element, :action_id)
  end

  test "a live incident is asked when the next update is due" do
    assert_includes block_ids(build), "field_next_update_block"
  end

  test "picking a status that closes the incident takes the timer off the form" do
    view = build(state: picked("resolved"))

    assert_not_includes block_ids(view), "field_next_update_block"
    assert_includes block_ids(view), "field_status_block"
  end

  test "picking a status that cancels the incident takes the timer off the form" do
    assert_not_includes block_ids(build(state: picked("canceled"))), "field_next_update_block"
  end

  test "moving between live statuses leaves the timer in place" do
    assert_includes block_ids(build(state: picked("monitoring"))), "field_next_update_block"
  end

  private

  def build(state: {})
    Slack::Modals::IncidentUpdate.build(@incident, state: state)
  end

  def picked(slug)
    {
      "field_status_block" => {
        Identifiers::INCIDENT_UPDATE_STATUS_SELECT => { "selected_option" => { "value" => slug } }
      }
    }
  end

  def block_ids(view)
    view[:blocks].map { |block| block[:block_id] }
  end

  def status_block(view)
    view[:blocks].find { |block| block[:block_id] == "field_status_block" }
  end
end
