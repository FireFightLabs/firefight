require "test_helper"

module Integrations
  module Sandboxes
    class NorthflankTest < ActiveSupport::TestCase
      setup do
        ENV.stubs(:[]).with(anything).returns(nil)
        ENV.stubs(:[]).with("NORTHFLANK_API_TOKEN").returns("nf_token")
        ENV.stubs(:[]).with("NORTHFLANK_SANDBOX_PROJECT").returns("firefight")
      end

      test "a box is a private service from the sandbox image, reached by its name inside the project" do
        sent = nil
        Http.expects(:request).with do |uri, request, **|
          sent = [ uri, request ]
          true
        end.returns(response(201, { "data" => { "id" => "halon-box-1" } }))

        box = Northflank.new.start(name: "halon-box-1")

        uri, request = sent
        body = JSON.parse(request.body)
        assert_equal "/v1/projects/firefight/services/deployment", uri.path
        assert_equal "Bearer nf_token", request["Authorization"]
        assert_equal [ { "name" => "cmd", "internalPort" => 8080, "public" => false, "protocol" => "HTTP" } ], body["ports"]
        assert_equal Sandboxes.image, body.dig("deployment", "external", "imagePath")
        assert_equal box.key, body.dig("runtimeEnvironment", "SANDBOX_KEY")
        assert_equal "http://halon-box-1:8080", box.address
      end

      test "an app in the boxes' own project reaches a box by its service id alone" do
        ENV.stubs(:[]).with("NF_PROJECT_ID").returns("firefight")
        Http.expects(:request).once.returns(response(201, { "data" => { "id" => "halon-box-1" } }))

        assert_equal "http://halon-box-1:8080", Northflank.new.start(name: "halon-box-1").address
      end

      test "an app in another project reaches a box at the address for projects allowed in" do
        ENV.stubs(:[]).with("NF_PROJECT_ID").returns("firefight-app")
        paths = []
        Http.expects(:request).twice.with { |uri, *| paths << uri.path }.returns(
          response(200, { "data" => { "id" => "firefight", "networking" => { "allowedIngressProjects" => [ "firefight-app" ] },
                                      "cluster" => { "namespace" => "ns-8zy2mcjh9zn2" } } }),
          response(201, { "data" => { "id" => "halon-box-1" } })
        )

        box = Northflank.new.start(name: "halon-box-1")

        assert_equal [ "/v1/projects/firefight", "/v1/projects/firefight/services/deployment" ], paths
        assert_equal "http://halon-box-1.ns-8zy2mcjh9zn2:8080", box.address
      end

      test "a project that does not say who it lets in is still reached by its namespace" do
        ENV.stubs(:[]).with("NF_PROJECT_ID").returns("firefight-app")
        Http.stubs(:request).returns(
          response(200, { "data" => { "id" => "firefight", "cluster" => { "namespace" => "ns-8zy2mcjh9zn2" } } }),
          response(201, { "data" => { "id" => "halon-box-1" } })
        )

        assert_equal "http://halon-box-1.ns-8zy2mcjh9zn2:8080", Northflank.new.start(name: "halon-box-1").address
      end

      test "a boxes' project that does not let the app's project in is named before any box is made" do
        ENV.stubs(:[]).with("NF_PROJECT_ID").returns("firefight-app")
        Http.expects(:request).once.returns(response(200, { "data" => {
          "id" => "firefight", "networking" => { "allowedIngressProjects" => [] }, "cluster" => { "namespace" => "ns-8zy2mcjh9zn2" }
        } }))

        error = assert_raises(Error) { Northflank.new.start(name: "halon-box-1") }
        assert_equal "Northflank project firefight (NORTHFLANK_SANDBOX_PROJECT) does not allow ingress from firefight-app, " \
                     "the app's project. Add firefight-app to its ingress projects in the project's networking settings.", error.message
      end

      test "Northflank's own refusal is what the error says" do
        Http.stubs(:request).returns(response(409, { "error" => { "message" => "Storage class nvme doesn't support that" } }))

        error = assert_raises(Error) { Northflank.new.start(name: "halon-box-1") }
        assert_equal "Northflank 409: Storage class nvme doesn't support that", error.message
      end

      test "only services named like a box are listed, so the sweep never touches the app" do
        Http.stubs(:request).returns(response(200, { "data" => { "services" => [
          { "id" => "halon-box-1", "name" => "halon-box-1", "createdAt" => "2026-09-24T10:00:00Z" },
          { "id" => "web", "name" => "web", "createdAt" => "2026-09-01T10:00:00Z" }
        ] } }))

        assert_equal [ "halon-box-1" ], Northflank.new.running.map(&:ref)
      end

      test "what Northflank holds is listed with its deployment state in one vocabulary" do
        Http.stubs(:request).returns(response(200, { "data" => { "services" => [
          { "id" => "halon-box-1", "name" => "halon-box-1", "createdAt" => "2026-09-24T10:00:00Z", "status" => { "deployment" => { "status" => "FAILED" } } },
          { "id" => "web", "name" => "web", "createdAt" => "2026-09-01T10:00:00Z", "status" => { "deployment" => { "status" => "COMPLETED" } } }
        ] } }))

        held = Northflank.new.inventory

        assert_equal [ [ "halon-box-1", "FAILED", ProviderSandbox::PHASE_FAILED ] ], held.map { |box| [ box.ref, box.state, box.phase ] }
      end

      test "without a project to put boxes in it says which setting is missing" do
        ENV.stubs(:[]).with("NORTHFLANK_SANDBOX_PROJECT").returns(nil)

        error = assert_raises(Error) { Northflank.new.start(name: "halon-box-1") }
        assert_equal "NORTHFLANK_SANDBOX_PROJECT is not set.", error.message
      end

      private

      def response(code, body) = stub(code: code.to_s, body: body.to_json)
    end
  end
end
