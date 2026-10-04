require "test_helper"

class IntegrationProviderRegionsTest < ActiveSupport::TestCase
  test "a provider with regions reaches its first one unless told otherwise, and a pasted address is in the region its host is" do
    datadog = IntegrationProvider.find("datadog")

    assert datadog.regional?
    assert_equal "https://mcp.datadoghq.com/v1/mcp", datadog.server_url
    assert_equal "us1", datadog.region.key
    assert_equal "https://app.datadoghq.eu", datadog.region("eu1").site
    assert_nil datadog.region("mars1")
    assert_equal "us5", datadog.region_for_url("https://MCP.us5.datadoghq.com/api/unstable/mcp-server/mcp").key
    assert_nil datadog.region_for_url("https://example.com/mcp")
    assert_not IntegrationProvider.find("linear").regional?
  end

  test "regions and a server of its own, or a key listed twice, are refused when the registry loads" do
    region = { "key" => "us", "label" => "US", "server_url" => "https://mcp.example/mcp" }

    assert_raises(ArgumentError) { IntegrationProvider.send(:regions_of, { "key" => "acme", "server_url" => "https://x/mcp", "regions" => [ region ] }) }
    assert_raises(ArgumentError) { IntegrationProvider.send(:regions_of, { "key" => "acme", "regions" => [ region, region ] }) }
    field = { "key" => "org", "label" => "Organization", "hint" => "Its slug." }
    assert_raises(ArgumentError) { IntegrationProvider.send(:connect_fields_of, { "key" => "acme", "connect_fields" => [ field, field ] }) }
  end

  test "a connect field says what is wrong with a value, and an optional one may be empty" do
    org = IntegrationProvider::ConnectField.new(key: "org", label: "Organization", hint: "Its slug.", path: true)
    account = IntegrationProvider::ConnectField.new(key: "account", label: "Account", hint: "Its number.", numeric: true, optional: true)

    assert_equal "Organization is required.", org.refusal(" ")
    assert_equal "Organization can hold only letters, numbers, dots, dashes, underscores and tildes.", org.refusal("acme/../x")
    assert_nil org.refusal("acme-co")
    assert_nil account.refusal("")
    assert_equal "Account must be a number.", account.refusal("12a")
  end

  test "only categories a provider is in are offered" do
    assert IntegrationProvider.categories.keys.all? { |name| IntegrationProvider.all.any? { |entry| entry.category == name } }
    assert_includes IntegrationProvider.categories.keys, "Observability"
  end
end
