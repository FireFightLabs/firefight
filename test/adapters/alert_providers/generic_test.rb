require "test_helper"

class AlertProviders::GenericTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one),
                                  name: "Custom", provider: AlertSource::PROVIDER_GENERIC)
  end

  test "custom field_map with array-index paths extracts nested values" do
    @source.update!(config: { "field_map" => { "title" => "alert.name", "service" => "labels.0.service" } })
    payload = { "alert" => { "name" => "DB down" }, "labels" => [ { "service" => "api" } ] }

    item = AlertProviders::Generic.normalize(payload, source: @source).first

    assert_equal "DB down", item[:fields]["title"]
    assert_equal "api", item[:fields]["service"]
    assert_equal payload, item[:payload]
  end

  test "items_path splits a batch into per-item alerts with payload slices" do
    @source.update!(config: { "items_path" => "alerts", "field_map" => { "title" => "annotations.summary" } })
    payload = {
      "alerts" => [
        { "annotations" => { "summary" => "one" } },
        { "annotations" => { "summary" => "two" } }
      ]
    }

    items = AlertProviders::Generic.normalize(payload, source: @source)

    assert_equal 2, items.size
    assert_equal "one", items.first[:fields]["title"]
    assert_equal({ "annotations" => { "summary" => "two" } }, items.last[:payload])
  end

  test "items_path pointing at a non-array yields no items" do
    @source.update!(config: { "items_path" => "alerts" })

    assert_empty AlertProviders::Generic.normalize({ "alerts" => "nope" }, source: @source)
  end

  test "a payload where no mapped field resolves is unrecognized" do
    assert_empty AlertProviders::Generic.normalize({ "unrelated" => "junk" }, source: @source)
  end

  test "resolved status values normalize to resolved" do
    item = AlertProviders::Generic.normalize({ "title" => "x", "status" => "OK" }, source: @source).first

    assert_equal Alert::STATUS_RESOLVED, item[:fields]["status"]
  end

  test "a padded resolved status still normalizes to resolved" do
    item = AlertProviders::Generic.normalize({ "title" => "x", "status" => " ok \n" }, source: @source).first

    assert_equal Alert::STATUS_RESOLVED, item[:fields]["status"]
  end

  test "a padded unrecognized status still normalizes to firing" do
    item = AlertProviders::Generic.normalize({ "title" => "x", "status" => " alerting " }, source: @source).first

    assert_equal Alert::STATUS_FIRING, item[:fields]["status"]
  end
end
