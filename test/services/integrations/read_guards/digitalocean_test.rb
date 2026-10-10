require "test_helper"

module Integrations
  module ReadGuards
    class DigitaloceanTest < ActiveSupport::TestCase
      test "a GET to a path of the API reads, and credentials and signed log addresses are refused by Firefight's rule" do
        assert Digitalocean.reads?(ApiReads::TOOL, "path" => "/v2/apps/app-1/deployments")

        %w[/v2/kubernetes/clusters/k-1/kubeconfig /v2/kubernetes/clusters/k-1/credentials /v2/registry/docker-credentials
           /v2/apps/app-1/logs /v2/apps/app-1/deployments/d-1/components/web/logs].each do |path|
          assert_raises(PolicyRefusal, path) { Digitalocean.reading(ApiReads::TOOL, "path" => path) }
        end
      end

      test "a database's users and pools, Spaces keys, a Functions namespace and API keys are read as names" do
        %w[/v2/databases/db-1/users /v2/databases/db-1/pools /v2/spaces/keys /v2/functions/namespaces/fn-1 /v2/gen-ai/agents/a-1/api_keys].each do |path|
          assert Digitalocean.secret?(path), path
        end
        assert_not Digitalocean.secret?("/v2/databases/db-1")
      end
    end
  end
end
