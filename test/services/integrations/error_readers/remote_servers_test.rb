require "test_helper"

module Integrations
  module ErrorReaders
    # Each provider's not found as its server words it, from the server's own code or seen from the hosted server, and
    # failures from the same server that are not one.
    class RemoteServersTest < ActiveSupport::TestCase
      SAID = {
        Neon => {
          not_found: [ "Not Found\n[HTTP 404] Not Found", "project not found\n[HTTP 404] project not found" ],
          other: [ "[HTTP 404] logs are off (reason: telemetry_not_enabled)", "[HTTP 404] this project is outside the project the key is for",
                   "[HTTP 500] internal error", "NotFoundError: Please provide a project ID or ensure you have only one project" ]
        },
        Planetscale => {
          not_found: [ '{"code":"not_found","message":"Not Found"}',
                       "Error: Insights not found. Please check your organization, database, and branch names. (status: 404)" ],
          other: [ '{"code":"forbidden","message":"Forbidden"}', "Error: Something went wrong (status: 500)" ]
        },
        Upstash => {
          not_found: [ "Error: Request failed (404 Not Found): {\"error\":\"database not found\"}", "Error: Request failed (404 ): nope" ],
          other: [ "Error: Request failed (401 Unauthorized): bad token", "Error: Redis error: WRONGTYPE" ]
        },
        Sentry => {
          not_found: [ "**Input Error**\n\nThere was an HTTP 404 error with your request to the Sentry API.\n\nAPI error (404): The requested resource does not exist." ],
          other: [ "**Input Error**\n\nThere was an HTTP 403 error with your request to the Sentry API.\n\nAPI error (403): You do not have permission." ]
        },
        Grafana => {
          not_found: [ "datasource with UID 'abc' not found. Please check if the datasource exists and is accessible",
                       "get dashboard by uid X: [GET /dashboards/uid/{uid}][404] getDashboardByUidNotFound {\"message\":\"Dashboard not found\"}",
                       "get dashboard \"X\" via k8s api: kubernetes API error: 404 Not Found (HTTP 404): gone",
                       "tempo API returned 404: trace not found", "loki API returned status code 404: nope", "panel with ID 7 not found" ],
          other: [ "loki API returned status code 400: parse error", "[GET /dashboards/uid/{uid}][403] getDashboardByUidForbidden {}" ]
        },
        Posthog => {
          not_found: [ "Error: [insight-get]: Request failed:\nPath: GET /api/projects/1/insights/999/\nStatus Code: 404 (Not Found)\nError Message: {\"detail\":\"Not found.\"}",
                       "Experiment 42 not found in this project. If the id is correct, call experiment-list" ],
          other: [ "Error: [insight-get]: Request failed:\nPath: GET /api/projects/1/insights/\nStatus Code: 400 (Bad Request)\nError Message: {}" ]
        },
        Openstatus => {
          not_found: [ "monitor 123 not found", "page_subscriber not found", "External service component not found" ],
          other: [ "Invalid input: name is required", "The monitor named not found.example.com could not be checked in time" ]
        },
        Honeybadger => {
          not_found: [ "Failed to get project: HTTP 404: Project not found" ],
          other: [ "Failed to get project: HTTP 401: Unauthorized", "Insights query error: bad query" ]
        },
        Signoz => {
          not_found: [ "SigNoz API error: unexpected status 404: metric not found: \"x\"", "SigNoz API error: unexpected status 404" ],
          other: [ "SigNoz API error: unexpected status 404: route not found", "SigNoz API error: unexpected status 500" ]
        },
        Pagerduty => {
          not_found: [ "Error executing tool get_incident: GET https://api.pagerduty.com/incidents/X: API responded with client error (status 404): {\"error\":{\"message\":\"Not Found\",\"code\":2100}}",
                       "Error executing tool get_technical_service_dependencies: 404 Client Error: Not Found for url: https://api.pagerduty.com/x",
                       "PagerDuty v3 Schedules API error (HTTP 404): Not Found" ],
          other: [ "Error executing tool get_incident: GET https://api.pagerduty.com/incidents: API responded with client error (status 403): {}" ]
        },
        Notion => {
          not_found: [ '{"name":"APIResponseError","code":"object_not_found","status":404,"message":"Could not find page with ID: 0f1e2d3c."}' ],
          other: [ '{"name":"APIResponseError","code":"restricted_resource","status":403,"message":"Could not find what you asked for."}',
                   '{"name":"APIResponseError","code":"validation_error","status":400}' ]
        }
      }.freeze

      SAID.each do |reader, said|
        test "#{reader.name.demodulize} tells its not found from its other failures" do
          said[:not_found].each { |text| assert reader.not_found?(text), text }
          said[:other].each { |text| assert_not reader.not_found?(text), text }
        end
      end

      test "every reader is named by its provider's definition, so a not found from its server reaches a step" do
        SAID.each_key do |reader|
          assert_equal reader, Provider.for(reader.name.demodulize.underscore).error_reader
        end
      end
    end
  end
end
