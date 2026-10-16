require "test_helper"

# script/provider_docs/api_client_endpoints.mjs on a client of two endpoint classes, run as ProviderDocs::Package runs
# it, under Node's permission model. The calls the provider documents beside its client's join the reference, so a call
# that exists is never read as one the API does not offer.
class ProviderDocs::ApiClientEndpointsTest < ActiveSupport::TestCase
  SCRIPT = ProviderDocs::Package::SCRIPT

  CLIENT = <<~JS.freeze
    class GetJobEndpoint {
      constructor() { this.method = "GET"; this.description = "Get a job"; this.requiredPermissions = "Project > Jobs > General > Read" }
      endpointUrl(opts) { return `/v1/projects/${opts.parameters.projectId}/jobs/${opts.parameters.jobId}` }
    }
    class GetJobLogsEndpoint {
      constructor() { this.method = "GET"; this.description = "Logs the client defines" }
      endpointUrl(opts) { return `/v1/projects/${opts.parameters.projectId}/jobs/${opts.parameters.jobId}/build-logs` }
    }
    module.exports = { GetJobEndpoint, GetJobLogsEndpoint }
  JS

  test "documented calls join the client's own under their area, each with its query names, and one the client defines is not written twice" do
    Dir.mktmpdir do |dir|
      install = File.join(dir, "package")
      out = File.join(dir, "pages")
      client = File.join(install, "node_modules", "fake-client")
      FileUtils.mkdir_p([ client, out ])
      File.write(File.join(install, "package.json"), "{}")
      File.write(File.join(client, "package.json"), { name: "fake-client", version: "1.0.0", main: "index.js", types: "index.d.ts" }.to_json)
      File.write(File.join(client, "index.js"), CLIENT)
      File.write(File.join(client, "index.d.ts"), "")
      paths = File.join(install, ProviderDocs::Package::PATHS_FILE)
      File.write(paths, [
        { method: "GET", path: "jobs/{jobId}/logs", description: "Get logs for a job, or one of its runs by runId.", permission: "Project > Jobs > Deployment > View Observability",
          query: %w[runId startTime] },
        { method: "GET", path: "jobs/{jobId}/build-logs", description: "Get logs for a job build." }
      ].to_json)

      _output, error, status = Open3.capture3({ "PATH" => ENV.fetch("PATH") }, "node", "--permission", "--allow-fs-read=#{install}", "--allow-fs-read=#{SCRIPT.dirname}",
                                              "--allow-fs-write=#{out}", SCRIPT.to_s, install, "fake-client", out, "/v1/projects/{projectId}/", paths,
                                              unsetenv_others: true)
      assert status.success?, error

      jobs = File.read(File.join(out, "project", "jobs.md"))
      assert_match "### GET jobs/{jobId}/logs\n\nGet logs for a job, or one of its runs by runId. Documented in the provider's API reference", jobs
      assert_match "Query: runId, startTime.\nPermission: Project > Jobs > Deployment > View Observability.", jobs
      assert_equal 1, jobs.scan("### GET jobs/{jobId}/build-logs").size
      assert_match "Logs the client defines.", jobs
      assert_match "- GET jobs/{jobId}/logs", File.read(File.join(out, "index.md"))
    end
  end

  test "Northflank's logs and metrics calls are documented beside its client's, and api_request checks their query names" do
    definition = ProviderDocSource::Definition.find("northflank")
    store_doc_page(provider: "northflank", path: "api/project/jobs.md", content: "# jobs\n\n### GET jobs/{jobId}/logs\n\nGet logs for a job.\nQuery: runId, startTime.")
    assert_equal %w[runId startTime], Integrations::Packs::Northflank::ApiReference.query_names("GET", "jobs/nightly/logs")

    documented = definition["paths"].map { |call| call.values_at("method", "path") }
    assert_includes documented, [ "GET", "jobs/{jobId}/logs" ]
    assert_includes documented, [ "GET", "jobs/{jobId}/metrics" ]
    assert_includes documented, [ "GET", "services/{serviceId}/build-logs" ]
    assert(definition["paths"].all? { |call| call["description"].end_with?(".") && call["permission"].present? })
  end
end
