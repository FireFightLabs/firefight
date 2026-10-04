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
    slug = "Organization can hold only letters, numbers, dots, dashes and underscores, starting with a letter or number."
    [ "acme/x", "acme?x=1", "acme#x", "..", ".acme", "-acme", "acme x", "acme%2Fx" ].each { |value| assert_equal slug, org.refusal(value), value }
    assert_nil org.refusal("acme-co.eu_1")
    assert_nil account.refusal("")
    assert_equal "Account must be a number.", account.refusal("12a")
  end

  test "a field may declare its own shape, and says in words what it allows" do
    region = IntegrationProvider::ConnectField.new(key: "region", label: "Region", hint: "Its code.", pattern: "[a-z]{2}[0-9]", allowed: "two letters and a digit")

    assert_nil region.refusal("eu1")
    assert_equal "Region can hold only two letters and a digit.", region.refusal("eu-1")
    assert_raises(ArgumentError) { IntegrationProvider::ConnectField.new(key: "x", label: "X", hint: "X.", pattern: "[a-z]+") }
    assert_nil IntegrationProvider::ConnectField.new(key: "note", label: "Note", hint: "Anything.").refusal("a/b ?#")
  end

  test "a field that picks from a list takes only its options, one or several" do
    options = [ { "value" => "us-east-1", "label" => "US East" }, { "value" => "eu-west-1", "label" => "Europe" } ]
    regions = IntegrationProvider::ConnectField.new(key: "regions", label: "Regions", hint: "Where it runs.", multiple: true, options: options)
    cloud = IntegrationProvider::ConnectField.new(key: "cloud", label: "Cloud", hint: "Which one.", options: options)

    assert_equal %w[us-east-1 eu-west-1], regions.value_of([ " us-east-1", "eu-west-1", "", "us-east-1" ])
    assert_nil regions.refusal(%w[us-east-1 eu-west-1])
    assert_equal "Regions is required.", regions.refusal([])
    assert_equal "Regions can only be US East or Europe.", regions.refusal(%w[us-east-1 ap-south-1])
    assert_equal "US East, Europe", regions.shown(%w[us-east-1 eu-west-1])
    assert_nil cloud.refusal("eu-west-1")
    assert_equal "Cloud can only be US East or Europe.", cloud.refusal("mars")
    assert_raises(ArgumentError) { IntegrationProvider::ConnectField.new(key: "x", label: "X", hint: "X.", multiple: true) }
    assert_raises(ArgumentError) { IntegrationProvider::ConnectField.new(key: "x", label: "X", hint: "X.", multiple: true, options: options, path: true) }
  end

  test "each part of the address is escaped, so a value can never be more than one segment of it" do
    entry = IntegrationProvider::Entry.new(
      key: "acme", name: "Acme", category: "Observability", mark: "AC", color: "#000000", description: "Acme.", kind: Integration::KIND_MCP,
      server_url: "https://mcp.acme.example/mcp/", source_links: IntegrationProvider::SOURCE_LINKS_NONE, map: IntegrationProvider::MAP_NONE,
      connect_fields: [ IntegrationProvider::ConnectField.new(key: "org", label: "Organization", hint: "Its slug.", path: true) ]
    )

    assert_equal "https://mcp.acme.example/mcp/acme-co", entry.server_url_for(nil, "org" => "acme-co")
    assert_equal "https://mcp.acme.example/mcp/acme%2Fx%3Fy%23z", entry.server_url_for(nil, "org" => "acme/x?y#z")
  end

  test "only categories a provider is in are offered" do
    assert IntegrationProvider.categories.keys.all? { |name| IntegrationProvider.all.any? { |entry| entry.category == name } }
    assert_includes IntegrationProvider.categories.keys, "Observability"
  end
end
