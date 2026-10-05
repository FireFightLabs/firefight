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
  # checked each day by SkillCheckJob.
  test "every tool and parameter a native provider's skill names is one its pack declares" do
    Chat::Skill.all.reject(&:firefight?).each do |skill|
      pack = Integrations::NativePack.for(skill.source)
      next unless pack

      # A skill can name the capabilities that answer for the provider's resources, with their parameters.
      adapter = Integrations::Capabilities.adapter_for(skill.source)
      capabilities = Integrations::Capabilities::SPECS.values.select { |spec| adapter&.const_get(:TOOLS)&.key?(spec.key) }.index_by(&:tool_name)
      definitions = pack.tool_definitions.index_by(&:name)
      skill.tools.each { |tool| assert_includes definitions.keys + capabilities.keys, tool, "#{skill.name} names #{tool}" }
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
        skill.tools.each { |tool| assert_includes documented + capabilities, tool, "#{skill.name} names #{tool}" }
        skill.steps.scan(/`([^`]+)`/).flatten.each { |name| assert_includes skill.tools, name, "#{skill.name} calls #{name} without listing it" }
      end
    end
  end

  test "every guide a skill lists is one its source keeps, and a source's guides carry their license and origin" do
    Chat::Skill.all.each do |skill|
      skill.references.each do |path|
        assert_includes Chat::Skill.references_of(skill.source), path, "#{skill.name} lists #{path}, which #{skill.source} does not keep"
      end
    end
    Dir[Chat::Skill::DIRECTORY.join("*", Chat::Skill::REFERENCES)].each do |folder|
      assert File.exist?(File.join(folder, "LICENSE")), "#{folder} has no LICENSE"
      assert File.exist?(File.join(folder, "SOURCE")), "#{folder} does not say where it came from"
    end
  end

  # Seen in a real chat, a path block on Cloudflare was written without this skill, since it named only addresses.
  test "the Cloudflare block skill covers paths, checking a rule expression and reading where Cloudflare stopped parsing it" do
    skill = Chat::Skill.find("cloudflare_block")

    assert_match "path", skill.used_when
    assert_match "every ( has its )", skill.steps
    assert_match "20127", skill.steps
    assert_includes skill.references, "rules/operators.md"
    assert_includes Chat::Skill.reference("cloudflare", "rules/operators.md"), "Grouping symbols"
  end

  test "a guide is never read as a skill, and nothing outside a source's guides can be read" do
    assert Chat::Skill.all.none? { |skill| skill.domain == Chat::Skill::REFERENCES }
    assert_includes Chat::Skill.reference("planetscale", "postgres/ps-connections.md"), "PgBouncer"
    assert_nil Chat::Skill.reference("planetscale", "../databases/triage.md")
    assert_nil Chat::Skill.reference("planetscale", "../../../master.key")
  end
end
