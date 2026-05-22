require "test_helper"

class Slack::BlockValueExtractorTest < ActiveSupport::TestCase
  test "returns nil when the block is absent" do
    assert_nil Slack::BlockValueExtractor.extract(
      {},
      block_id: "field_name_block",
      action_id: "field_name_input",
      field_type: IncidentFieldDefinition::TYPE_TEXT
    )
  end

  test "returns nil when the action is absent under the block" do
    values = { "field_name_block" => { "other_action" => { "value" => "ignored" } } }

    assert_nil Slack::BlockValueExtractor.extract(
      values,
      block_id: "field_name_block",
      action_id: "field_name_input",
      field_type: IncidentFieldDefinition::TYPE_TEXT
    )
  end

  test "extracts plain text value for TYPE_TEXT" do
    values = { "field_name_block" => { "field_name_input" => { "value" => "Outage" } } }

    assert_equal "Outage", Slack::BlockValueExtractor.extract(
      values,
      block_id: "field_name_block",
      action_id: "field_name_input",
      field_type: IncidentFieldDefinition::TYPE_TEXT
    )
  end

  test "extracts plain value for TYPE_NUMBER and TYPE_LINK (fallback branch)" do
    values = { "n" => { "i" => { "value" => "42" } } }

    assert_equal "42", Slack::BlockValueExtractor.extract(values, block_id: "n", action_id: "i", field_type: IncidentFieldDefinition::TYPE_NUMBER)
    assert_equal "42", Slack::BlockValueExtractor.extract(values, block_id: "n", action_id: "i", field_type: IncidentFieldDefinition::TYPE_LINK)
  end

  test "extracts selected_option.value for TYPE_SINGLE_SELECT" do
    values = {
      "field_severity_block" => {
        "field_severity_input" => { "selected_option" => { "value" => "critical", "text" => { "type" => "plain_text", "text" => "Critical" } } }
      }
    }

    assert_equal "critical", Slack::BlockValueExtractor.extract(
      values,
      block_id: "field_severity_block",
      action_id: "field_severity_input",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT
    )
  end

  test "extracts selected_option.value for TYPE_CATALOG_REFERENCE" do
    values = {
      "field_service_block" => {
        "field_service_input" => { "selected_option" => { "value" => "entry_123" } }
      }
    }

    assert_equal "entry_123", Slack::BlockValueExtractor.extract(
      values,
      block_id: "field_service_block",
      action_id: "field_service_input",
      field_type: IncidentFieldDefinition::TYPE_CATALOG_REFERENCE
    )
  end

  test "returns nil when single-select block exists but no option is selected" do
    values = { "b" => { "i" => { "selected_option" => nil } } }

    assert_nil Slack::BlockValueExtractor.extract(
      values,
      block_id: "b",
      action_id: "i",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT
    )
  end

  test "extracts an array of selected_options for TYPE_MULTI_SELECT" do
    values = {
      "field_tags_block" => {
        "field_tags_input" => {
          "selected_options" => [
            { "value" => "alpha" },
            { "value" => "beta" }
          ]
        }
      }
    }

    assert_equal [ "alpha", "beta" ], Slack::BlockValueExtractor.extract(
      values,
      block_id: "field_tags_block",
      action_id: "field_tags_input",
      field_type: IncidentFieldDefinition::TYPE_MULTI_SELECT
    )
  end

  test "extracts an array of selected_options for TYPE_CATALOG_MULTI_REFERENCE" do
    values = {
      "b" => { "i" => { "selected_options" => [ { "value" => "e1" }, { "value" => "e2" } ] } }
    }

    assert_equal [ "e1", "e2" ], Slack::BlockValueExtractor.extract(
      values,
      block_id: "b",
      action_id: "i",
      field_type: IncidentFieldDefinition::TYPE_CATALOG_MULTI_REFERENCE
    )
  end

  test "returns nil for multi-select when selected_options is missing" do
    values = { "b" => { "i" => {} } }

    assert_nil Slack::BlockValueExtractor.extract(
      values,
      block_id: "b",
      action_id: "i",
      field_type: IncidentFieldDefinition::TYPE_MULTI_SELECT
    )
  end

  test "returns an empty array for multi-select when selected_options is empty" do
    values = { "b" => { "i" => { "selected_options" => [] } } }

    assert_equal [], Slack::BlockValueExtractor.extract(
      values,
      block_id: "b",
      action_id: "i",
      field_type: IncidentFieldDefinition::TYPE_MULTI_SELECT
    )
  end
end
