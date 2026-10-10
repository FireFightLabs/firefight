require "test_helper"

module Integrations
  module Packs
    # Kubernetes' general read, api_read, kept to the namespaces the connection reaches, and its guard.
    class KubernetesReadsTest < ActiveSupport::TestCase
      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "kubernetes", name: "Cluster")
        @row = @integration.integration_environments.create!
        @row.store_fields!(Kubernetes::NAMESPACES => "shop")
        Kubernetes.stubs(:client_for).returns(KubernetesApi.allocate)
        @pack = Kubernetes.new(@integration)
      end

      test "api_read only reads, and an object in a namespace the connection reaches is read with secrets hidden" do
        assert Kubernetes.tool_definitions.find { |each| each.name == ApiReads::TOOL }.read_only
        KubernetesApi.any_instance.expects(:get).with("/api/v1/namespaces/shop/secrets/db", {}).returns(
          "metadata" => { "name" => "db", "namespace" => "shop" }, "data" => { "PASSWORD" => "aHVudGVyMg==" }
        )

        shown = text(call("path" => "/api/v1/namespaces/shop/secrets/db"))

        assert_match "Kubernetes answered GET /api/v1/namespaces/shop/secrets/db.", shown
        assert_includes shown, "PASSWORD"
        assert_not_includes shown, "aHVudGVyMg=="
      end

      test "a namespace the connection does not reach is refused, before the read when the path names it and after when a list holds it" do
        KubernetesApi.any_instance.expects(:get).with("/api/v1/namespaces/billing/pods", anything).never
        assert_raises(PolicyRefusal) { call("path" => "/api/v1/namespaces/billing/pods") }

        KubernetesApi.any_instance.stubs(:get).with("/api/v1/pods", {}).returns("items" => [ { "metadata" => { "namespace" => "shop" } }, { "metadata" => { "namespace" => "billing" } } ])
        error = assert_raises(PolicyRefusal) { call("path" => "/api/v1/pods") }
        assert_match "Name a namespace in the path", error.message
      end

      test "the guard refuses what reaches inside a running thing, and paths outside the API" do
        %w[/api/v1/namespaces/shop/pods/web/proxy/admin /api/v1/namespaces/shop/services/web:80/proxy /api/v1/nodes/n1/proxy/metrics
           /api/v1/namespaces/shop/pods/web/exec /api/v1/namespaces/shop/pods/web/portforward /metrics].each do |path|
          assert_not ReadGuards::Kubernetes.reads?(ApiReads::TOOL, "path" => path), path
        end
        assert ReadGuards::Kubernetes.reads?(ApiReads::TOOL, "path" => "/apis/apps/v1/namespaces/shop/deployments/web")
        assert ReadGuards::Kubernetes.reads?(ApiReads::TOOL, "path" => "/api/v1/namespaces/shop/pods/web/log")
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
