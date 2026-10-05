---
name: mixpanel_user_impact
when: Finding how many users an incident reaches in Mixpanel, when it began, and which countries, platforms or app versions it hits
tools: [get_events, list_properties, get_property_values, get_query_schema, run_query, get_report, search_entities]
references: [metrics/metric-anomaly.md, metrics/metric-rca.md, metrics/execution.md, reports/read-insights.md, reports/read-funnels.md]
---
1. When the team already watches a metric for this, use it. `search_entities` finds a saved report or board by name, and `get_report` reads it with its results.
2. Otherwise build the query. Call `get_query_schema` for the report type, insights for counts over time or funnels for a flow, and `run_query` with the event, unique users, by hour over the last seven days and by day over the last thirty. A drop at one hour that the days before do not have is the incident. A drop that repeats at the same hour each day is the daily pattern.
3. For a flow that fails partway, `run_query` a funnel across its steps before and during the incident. The step whose conversion fell is where people get stuck.
4. Find who is hit by breaking the drop down one property at a time, starting with mp_country_code, then $os, $browser and $app_version_string. Check with `list_properties` that the event carries the property, and `get_property_values` for its values, before filtering on it. One value owning most of the drop points at what broke. A filter or breakdown by cohort cannot run through Mixpanel's MCP server, so use properties instead.
5. State the number of people affected with its window, and say when Mixpanel's numbers may be incomplete because of a data quality issue.
