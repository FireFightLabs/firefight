---
name: posthog_user_impact
when: Finding how many users an incident reaches in PostHog, when it began, and which browsers, pages, countries or versions it hits
tools: [read_data_schema, query_trends, query_trends_actors, query_funnel, execute_sql, persons_retrieve]
references: [hogql/aggregations.md, hogql/useful-functions.md, hogql/sessions.md]
---
1. Call `read_data_schema` to find the events that stand for the broken step, such as a page, a click or a server event, and the properties they carry. Never guess an event name.
2. Call `query_trends` with those events in `series`, `math` dau, `interval` hour, a `dateRange` starting a day or more before the incident, and `compareFilter` with compare true. A drop against the previous period that starts at one hour is the incident. A drop that comes and goes every day is the daily pattern.
3. Break it down to find who is hit. Run the same query with a `breakdownFilter` on $browser, $os, $geoip_country_code, $current_url or $app_version, one at a time. One value owning most of the drop points at what broke.
4. For a flow that fails partway, call `query_funnel` across its steps before and during the incident. The step whose conversion fell is where people get stuck.
5. Count the people affected with `query_trends_actors` for the bucket that dropped, or `execute_sql` for an exact number, such as distinct person_id on $exception events since the incident began. State the number with its window.
6. Use `persons_retrieve` only to look at one affected person in detail. Never paste personal data from it into the incident.
