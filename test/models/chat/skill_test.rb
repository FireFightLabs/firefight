require "test_helper"

class Chat::SkillTest < ActiveSupport::TestCase
  test "every skill has a name of its own, says when it is used and names its tools" do
    names = Chat::Skill.all.map(&:name)

    assert names.any?
    assert_equal names.uniq, names
    Chat::Skill.all.each do |skill|
      assert skill.used_when.present?, "#{skill.name} says when it is used"
      assert skill.tools.any?, "#{skill.name} names its tools"
      assert skill.steps.present?, "#{skill.name} has steps"
    end
  end

  test "Firefight's own skills sit under the tool group they belong to" do
    groups = Chat::Tools::Groups::FIREFIGHT.map(&:key)

    Chat::Skill.all.select { |skill| skill.source == Chat::Skill::SOURCE_FIREFIGHT }.each do |skill|
      assert_includes groups, skill.domain, "#{skill.name} sits under #{skill.domain}, which is not a tool group"
    end
  end

  # A skill that names a tool or field that no longer exists would send the agent after something that is not there.
  test "every tool one of Firefight's skills names exists and is offered to Halon" do
    offered = Mcp::Tools.all.map { |tool_class| tool_class.name_value.to_s } - Chat::Tools::Groups::NOT_FOR_HALON

    Chat::Skill.all.select(&:firefight?).each do |skill|
      skill.tools.each { |tool| assert_includes offered, tool, "#{skill.name} names #{tool}" }
    end
  end

  test "every name one of Firefight's skills sets in code is one of its tools, their parameters, a form or a form field" do
    tool_classes = Mcp::Tools.all.index_by { |tool_class| tool_class.name_value.to_s }
    known_everywhere = IncidentForm::SLUGS + IncidentSystemField.constants.grep(/\AKEY_/).map { |key| IncidentSystemField.const_get(key) }

    Chat::Skill.all.select(&:firefight?).each do |skill|
      parameters = skill.tools.flat_map { |tool| tool_classes.fetch(tool).input_schema_value.to_h.fetch(:properties, {}).keys.map(&:to_s) }
      known = skill.tools + parameters + known_everywhere
      skill.steps.scan(/`([^`]+)`/).flatten.each do |name|
        assert_includes known, name, "#{skill.name} sets #{name} in code, which none of its tools, parameters or forms has"
      end
    end
  end

  test "a provider's skills sit under that provider's key and its category" do
    Chat::Skill.all.reject(&:firefight?).each do |skill|
      provider = IntegrationProvider.find(skill.source)
      assert provider, "#{skill.name} sits under #{skill.source}, which is not a provider"
      assert_equal IntegrationProvider.category_slug(provider.category), skill.domain, "#{skill.name} sits under the wrong category"
    end
  end

  # A native pack's tools are in this repository, so its skills are held to them here. A connected server's are
  # checked each day by SkillCheckJob, which is also how a provider reached through its server keeps its skills when
  # Firefight's own app with it has a pack.
  test "every tool and parameter a native provider's skill names is one its pack declares" do
    Chat::Skill.all.reject(&:firefight?).each do |skill|
      pack = Integrations::NativePack.for(skill.source)
      next unless pack && IntegrationProvider.find(skill.source)&.kind == Integration::KIND_NATIVE

      # A skill can name the capabilities that answer for the provider's resources, with their parameters.
      adapter = Integrations::Capabilities.adapter_for(skill.source)
      capabilities = Integrations::Capabilities::SPECS.values.select { |spec| adapter&.const_get(:TOOLS)&.key?(spec.key) }.index_by(&:tool_name)
      definitions = pack.tool_definitions.index_by(&:name)
      skill.tools.each { |tool| assert_includes definitions.keys + capabilities.keys + [ Chat::Tools::UseSkill::MAP ], tool, "#{skill.name} names #{tool}" }
      known = skill.tools + skill.tools.flat_map do |tool|
        capabilities[tool] ? Integrations::Capabilities.schema(capabilities[tool], []).fetch("properties").keys : definitions.fetch(tool).params_schema.fetch("properties", {}).keys
      end
      skill.steps.scan(/`([^`]+)`/).flatten.each do |name|
        assert_includes known, name, "#{skill.name} sets #{name} in code, which none of its tools or their parameters has"
      end
    end
  end

  # Sentry's server is open source, so its skills are held to the tools it defines, as a native pack's are to the pack.
  # test/fixtures/files/sentry_mcp_tools.txt is that list, with each tool's parameters, when the skills were written.
  test "every Sentry tool and parameter a Sentry skill names is one its server defines, reached the way the server offers it" do
    defined = file_fixture("sentry_mcp_tools.txt").readlines.reject { |line| line.start_with?("#") }.to_h do |line|
      name, surface, *parameters = line.split
      [ name, { surface: surface, parameters: parameters } ]
    end
    capabilities = Integrations::Capabilities::SPECS.values.select { |spec| Integrations::Capabilities::Sentry::TOOLS.key?(spec.key) }.map(&:tool_name)
    skills = Chat::Skill.all.select { |skill| skill.source == Integrations::Capabilities::Sentry::PROVIDER_KEY }

    assert_equal %w[sentry_bad_release sentry_errors sentry_triage], skills.map(&:name).sort
    skills.each do |skill|
      (skill.tools - capabilities).each { |tool| assert_equal "direct", defined.dig(tool, :surface), "#{skill.name} names #{tool}, which the server does not list" }
      run = skill.steps.scan(/with name (\w+)/).flatten
      run.each { |name| assert_equal "catalog", defined.dig(name, :surface), "#{skill.name} runs #{name}, which the server's catalog does not have" }
      # Issue properties a query names, from Sentry's search docs, docs/concepts/search/searchable-properties/issues.mdx.
      known = (skill.tools + run).flat_map { |name| defined.dig(name, :parameters).to_a } + %w[firstSeen lastSeen firstRelease]
      skill.steps.scan(/\b[a-z]+[A-Z][A-Za-z]*\b/).uniq.each { |word| assert_includes known, word, "#{skill.name} names #{word}, which none of its tools takes" }
    end
  end

  # These providers' servers are hosted by the provider, so their skills, and the tools Firefight calls itself, are held
  # to the tools each one documents, as Firefight names them (lower case, with every other character an underscore).
  DOCUMENTED_TOOLS = {
    # docs.honeycomb.io/integrations/mcp/tools
    "honeycomb" => %w[get_workspace_context get_environment get_dataset get_dataset_columns run_query get_query_results find_queries find_columns run_bubbleup
                      get_trace list_spans get_span_details get_service_map get_anomaly_service_profiles list_boards get_triggers get_slos list_recipients],
    # axiomhq/docs, console/intelligence/mcp-server/tools.mdx
    "axiom" => %w[querydataset getsavedqueries listdatasets getdatasetfields listmetrics listmetrictags getmetrictagvalues searchmetrics querymetrics
                  listdashboards getdashboard exportdashboard checkmonitors getmonitor getmonitorhistory listnotifiers],
    # BetterStackHQ/claude-plugin, skills/investigate-incident/SKILL.md, and betterstack.com/docs/getting-started/integrations/mcp
    "betterstack" => %w[incident incident_timeline incident_comments incidents chart_alerts monitor monitors monitor_response_times monitor_availability on_calls
                        on_call escalation_policy sources source source_fields applications errors error releases query_help metrics_schema metrics_query_help
                        errors_query_help query query_windows],
    # pydantic/logfire, docs/how-to-guides/mcp-server.md
    "logfire" => %w[query_run query_schema_reference query_find_exceptions_in_file project_list token_info project_logfire_link project_logfire_ui_link issue_list
                    alert_list alert_get alert_status alert_history dashboard_list dashboard_get],
    # openstatusHQ/openstatus, packages/services/src/agent-tools
    "openstatus" => %w[list_monitors get_monitor get_monitor_status get_monitor_summary list_response_logs get_response_log list_status_pages list_page_components
                       list_status_reports create_status_report add_status_report_update update_status_report resolve_status_report list_maintenances],
    # honeybadger-io/honeybadger-mcp-server, internal/hbmcp
    "honeybadger" => %w[list_projects get_project get_project_occurrence_counts get_project_report list_faults get_fault get_fault_counts list_fault_notices
                        list_fault_affected_users query_insights list_check_ins get_check_in list_alarms get_alarm get_alarm_history],
    # SigNoz/signoz-mcp-server, internal/handler/tools
    "signoz" => %w[signoz_list_services signoz_get_service_top_operations signoz_search_logs signoz_aggregate_logs signoz_search_traces signoz_aggregate_traces
                   signoz_get_trace_details signoz_list_alerts signoz_get_alert signoz_get_alert_history signoz_get_field_keys signoz_get_field_values
                   signoz_query_metrics signoz_list_metrics]
  }.freeze

  test "every tool these providers' skills or Firefight's own reads name is one the provider documents" do
    probes = Integrations::HealthProbes
    probe_tools = {
      "honeycomb" => [ probes::Honeycomb::WORKSPACE ], "axiom" => [ probes::Axiom::LIST_DATASETS ], "betterstack" => [ probes::Betterstack::MONITORS ],
      "logfire" => [ probes::Logfire::UI_LINK ], "openstatus" => [ probes::Openstatus::LIST_MONITORS ],
      "honeybadger" => [ probes::Honeybadger::LIST_PROJECTS, probes::Honeybadger::GET_PROJECT ], "signoz" => [ probes::Signoz::LIST_SERVICES ]
    }
    DOCUMENTED_TOOLS.each do |provider, documented|
      adapter = Integrations::Capabilities.adapter_for(provider)
      capabilities = adapter.capabilities.map { |key| Integrations::Capabilities.spec(key).tool_name }
      called = adapter::TOOLS.values + probe_tools.fetch(provider)
      called.each { |tool| assert_includes documented, tool, "#{provider} calls #{tool}" }
      skills = Chat::Skill.all.select { |skill| skill.source == provider }
      assert skills.size >= 2, "#{provider} has a triage skill and one per kind of incident"
      skills.each do |skill|
        skill.tools.each { |tool| assert_includes documented + capabilities + [ Chat::Tools::UseSkill::MAP ], tool, "#{skill.name} names #{tool}" }
        skill.steps.scan(/`([^`]+)`/).flatten.each { |name| assert_includes skill.tools, name, "#{skill.name} calls #{name} without listing it" }
      end
    end
  end

  test "every guide a skill lists is a page one of its provider's documentation sources can hold" do
    Chat::Skill.all.each do |skill|
      sources = ProviderDocSource::Definition.of(skill.source)
      skill.references.each do |path|
        assert sources.any? { |source| source.could_hold?(path) }, "#{skill.name} lists #{path}, which no #{skill.source} documentation source holds"
      end
    end
  end

  # Seen in a real chat, a path block on Cloudflare was written without this skill, since it named only addresses.
  test "the Cloudflare block skill covers paths, checking a rule expression and reading where Cloudflare stopped parsing it" do
    skill = Chat::Skill.find("cloudflare_block")

    assert_match "path", skill.used_when
    assert_match "every ( has its )", skill.steps
    assert_match "20127", skill.steps
    assert_includes skill.references, "rules/operators.md"
    assert ProviderDocSource::Definition.find("cloudflare").could_hold?("rules/operators.md")
  end

  # Seen in a real chat, a zone already on the map was found with execute, which asks the person to confirm every call.
  test "every Cloudflare skill starts from the zone on the map, and lists zones with execute only when the map lacks it" do
    skills = Chat::Skill.all.select { |skill| skill.source == "cloudflare" }

    assert_equal 6, skills.size
    skills.each do |skill|
      assert_includes skill.tools, Chat::Tools::UseSkill::MAP, "#{skill.name} names the map"
      assert_includes skill.tools, "resource_status", "#{skill.name} reads the zone where the map is not the person's to read"
      first = skill.steps.lines.find { |line| line.start_with?("1.", "Start from") }
      assert_match "`get_resource_map`", first, "#{skill.name} finds the zone on the map before anything else"
    end
    assert_match "Only when the zone is not on the map, find it with `execute`", Chat::Skill.find("cloudflare_triage").steps
  end

  # Seen in a real chat, asked how a part of the code worked, Halon fetched files one at a time and then said it had no
  # shell to look with.
  test "each code host's code skill reads many files with a shell or a search, and fetches single files only when it knows them" do
    %w[github_code gitlab_code bitbucket_code].each do |name|
      skill = Chat::Skill.find(name)

      assert_match "across many files", skill.used_when, name
      assert_equal %w[running_commit run_shell code_search], skill.tools.first(3), name
      broad = skill.steps.index("inspect one checkout broadly with `run_shell`")
      single = skill.steps.index("Call `fetch_file` only for one or two files you already know")
      assert broad && single && broad < single, "#{name} leads with run_shell before single files"
      assert_match "`code_search` with a `pattern`", skill.steps, name
      assert_match "`ask_language_server`", skill.steps, name
    end
  end

  # Seen in a real chat, asked to create a Northflank pipeline, Halon searched Northflank's site and guessed POST
  # pipelines three times, though Northflank's API has no call that creates one.
  test "Northflank's fixes skill sends Halon to the API reference before the web, and says what the API does not offer" do
    skill = Chat::Skill.find("northflank_fixes")

    assert_match "creating or changing a pipeline", skill.used_when
    assert_equal "api/index.md", skill.references.first
    assert_includes skill.references, "api/project/pipelines.md"
    assert_match "read api/index.md (use_skill with this skill and that reference)", skill.steps
    assert_match "Look there before searching the web", skill.steps
    assert_match "When the reference does not list an operation, Northflank's API does not offer it. Say so plainly", skill.steps
    assert_match "The API lists and reads pipelines, and has no call that creates one", skill.steps
    assert_match "open the project's Pipelines and create a new one", skill.steps
    assert_match "pipelines/<pipeline>/release-flows/<stage>", skill.steps
    assert_match "cannot be reached with `api_request`, so it is a step for a person", skill.steps
    assert_no_match "Northflank's API docs give", skill.steps
  end

  test "Northflank's fixes skill pages through a list with the query options the reference lists, and filters it" do
    steps = Chat::Skill.find("northflank_fixes").steps

    assert_match "Query options go in `query`, never in the path, and only the ones the reference lists under Query for that call", steps
    assert_match "pass per_page 100 in `query`, and while the pagination says hasNextPage is true, call again with cursor set to the cursor it gave", steps
    assert_match "Narrow a list with the filters its call lists instead of reading every page", steps
    assert_no_match "sends no query options", steps
  end

  # A skill that hands Halon a raw API tool without the provider's list of calls leaves it guessing paths.
  test "every skill that names a raw API tool lists the provider's endpoint reference, or finds the endpoint with search" do
    Chat::Skill.all.reject(&:firefight?).each do |skill|
      if skill.tools.include?("api_request")
        assert_includes skill.references, "api/index.md", "#{skill.name} names api_request without the endpoint reference"
      end
      assert_includes skill.tools, "search", "#{skill.name} names execute without search" if skill.tools.include?("execute")
    end
  end

  test "every provider with a general read has a skill for it, which names its API reference or where the provider publishes it" do
    readers = Integrations::Provider.all.select { |provider| provider.pack&.tool_definitions&.any? { |each| each.name == Integrations::ApiReads::TOOL } }.map(&:key)
    assert_includes readers, "render"

    readers.each do |provider|
      skills = Chat::Skill.all.select { |skill| skill.source == provider && skill.tools.include?(Integrations::ApiReads::TOOL) }
      assert skills.any?, "#{provider} has api_read and no skill naming it"
      skills.each do |skill|
        reference = skill.references.any? { |path| path.match?(%r{\Aapi/(.+/)?index\.md\z}) }
        assert reference || skill.steps.match?(%r{https://\S+}), "#{skill.name} names api_read without the API reference or where it is published"
      end
    end
  end

  test "a guide is read from the docs store with where it came from, and nothing the store does not hold can be named" do
    store_doc_page(provider: "planetscale", path: "postgres/ps-connections.md", content: "# Connections\n\nUse PgBouncer.",
                   url: "https://github.com/planetscale/database-skills/blob/HEAD/skills/postgres/references/ps-connections.md")

    guide = Chat::Skill.reference("planetscale", "postgres/ps-connections.md")
    assert guide.start_with?("Source: Connections, https://github.com/planetscale/database-skills/blob/HEAD/skills/postgres/references/ps-connections.md")
    assert_includes guide, "PgBouncer"
    assert_nil Chat::Skill.reference("planetscale", "../databases/triage.md")
    assert_nil Chat::Skill.reference("planetscale", "../../../master.key")
    assert_equal [ "postgres/ps-connections.md" ], Chat::Skill.references_of("planetscale")
  end

  test "a guide the provider's documentation dropped is named as missing, and one not read yet is not" do
    store_doc_page(provider: "planetscale", path: "postgres/other.md", content: "# Other")

    assert_includes Chat::Skill.missing_references.keys, "planetscale_connections"
    assert_not Chat::Skill.missing_references.key?("cloudflare_triage")
  end
end
