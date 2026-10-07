module Integrations
  module ErrorReaders
    # Grafana's server answers with the Go error each tool returned (grafana/mcp-grafana, tools.go), so the shape depends on
    # the client behind the tool. A datasource or panel looked up by name or id that is not there is said in words
    # (tools/datasources.go, tools/dashboard_helpers.go), and every HTTP client names the status: the API client's
    # "[GET /path][404] getDashboardByUidNotFound", the Kubernetes style "(HTTP 404)", and "status 404", "status code 404",
    # "returned 404" or "HTTP 404" from Tempo, Loki, alerting, OnCall, snapshots, rendering and plugins.
    module Grafana
      NOT_FOUND = Regexp.union(
        /\]\[404\] \w+NotFound/, /\(HTTP 404\)/, /\b(?:status(?: code)?|returned|HTTP) 404\b/,
        /\Adatasource with (?:UID|name) '[^']*' not found/, /\Apanel with ID \d+ not found/
      )

      def self.not_found?(said) = said.match?(NOT_FOUND)
    end
  end
end
