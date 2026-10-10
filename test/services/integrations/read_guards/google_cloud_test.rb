require "test_helper"

module Integrations
  module ReadGuards
    class GoogleCloudTest < ActiveSupport::TestCase
      test "a GET to an API named by its host reads, with its service, path and query" do
        read = GoogleCloud.reading(ApiReads::TOOL, "service" => "CloudBuild", "path" => "v1/projects/acme/builds", "query" => { "pageSize" => 5 })

        assert_equal({ "service" => "cloudbuild", "path" => "/v1/projects/acme/builds", "query" => { "pageSize" => "5" } }, read)
        assert GoogleCloud.reads?(ApiReads::TOOL, "service" => "run", "path" => "/v2/projects/acme/locations/us-central1/services")
        assert GoogleCloud.guards?(ApiReads::TOOL)
      end

      test "a host that is not one label of googleapis.com, a secret's value and an object's bytes are never read" do
        assert_raises(Refused) { GoogleCloud.reading(ApiReads::TOOL, "service" => "evil.example.com/x", "path" => "/v1/x") }
        assert_raises(Refused) { GoogleCloud.reading(ApiReads::TOOL, "service" => "", "path" => "/v1/x") }
        assert_not GoogleCloud.reads?(ApiReads::TOOL, "service" => "run.", "path" => "/v1/x")
        assert_raises(PolicyRefusal) { GoogleCloud.reading(ApiReads::TOOL, "service" => "secretmanager", "path" => "/v1/projects/acme/secrets/db/versions/latest:access") }
        assert_raises(PolicyRefusal) { GoogleCloud.reading(ApiReads::TOOL, "service" => "storage", "path" => "/storage/v1/b/acme/o/dump.sql", "query" => { "alt" => "media" }) }
        assert GoogleCloud.reads?(ApiReads::TOOL, "service" => "secretmanager", "path" => "/v1/projects/acme/secrets/db/versions")
      end

      test "the projects a path names are found, and an instance's metadata is read as its keys" do
        assert_equal %w[acme], GoogleCloud.projects_in("/compute/v1/projects/acme/zones/us-central1-a/instances")
        assert_equal %w[acme other], GoogleCloud.projects_in("/v1/projects/acme/x/projects/other/y")

        shown = GoogleCloud.hidden("items" => [ { "name" => "vm", "metadata" => { "fingerprint" => "f", "items" => [ { "key" => "startup-script", "value" => "export TOKEN=abc" } ] } } ])
        item = shown["items"].first["metadata"]["items"].first
        assert_equal [ "startup-script", ApiReads::HIDDEN ], item.values_at("key", "value")
      end
    end
  end
end
