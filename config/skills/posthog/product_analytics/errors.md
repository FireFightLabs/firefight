---
name: posthog_errors
when: Finding which errors PostHog caught during an incident, how many users and sessions they reach, and what those people were doing
tools: [query_error_tracking_issues_list, query_error_tracking_issue, query_error_tracking_issue_events, query_session_recordings_list, session_recording_get, apm_trace_get]
references: [error-tracking/monitoring.md, error-tracking/fingerprints.md, error-tracking/upload-source-maps.md]
---
1. Call `query_error_tracking_issues_list` with a `dateRange` covering the incident and a while before it. Each issue is one kind of error with its occurrences, users and sessions. Compare an issue first seen when the incident began with ones that were already there, and set `volumeResolution` to see when each spiked.
2. Narrow when there are many: `searchQuery` for the error text, `release` for one version, `url` for one page, `library` for the SDK that sent it. An issue only on one release points at that deploy.
3. Call `query_error_tracking_issue` with its `issueId` and `includeBreakdown` true for the full description and how it splits by browser, OS, URL and version.
4. Call `query_error_tracking_issue_events` with the `issueId` and `include` stacktrace for the file and line. A stack trace of minified code means source maps were not uploaded for that release, which the upload-source-maps guide explains.
5. The events carry $session_id. Call `query_session_recordings_list` with those `session_ids`, then `session_recording_get` for one, to see what the person did just before the error. An event with a trace id leads to the request behind it with `apm_trace_get`.
