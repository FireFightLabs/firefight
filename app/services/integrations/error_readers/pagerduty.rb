module Integrations
  module ErrorReaders
    # PagerDuty's server answers an API error with its status, "API responded with client error (status 404)",
    # "404 Client Error" or "(HTTP 404)" (PagerDuty/pagerduty-mcp-server, through python-pagerduty and
    # tools/schedules_v3.py), and PagerDuty documents 404 with code 2100 as not found.
    module Pagerduty
      NOT_FOUND = /\(status 404\)|\(HTTP 404\)|\b404 Client Error\b/

      def self.not_found?(said) = said.match?(NOT_FOUND)
    end
  end
end
