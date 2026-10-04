require "test_helper"
require "aws-sdk-ecs"
require "aws-sdk-lambda"

module Integrations
  class AwsApiTest < ActiveSupport::TestCase
    setup do
      @api = AwsApi.new(access_key_id: "AKIAEXAMPLE", secret_access_key: "secret")
    end

    test "a client is built per service and region with the keys, and reused" do
      client = @api.send(:client, :ecs, "eu-west-1")

      assert_kind_of ::Aws::ECS::Client, client
      assert_equal "eu-west-1", client.config.region
      assert_equal "AKIAEXAMPLE", client.config.credentials.access_key_id
      assert_same client, @api.send(:client, :ecs, "eu-west-1")
      assert_not_same client, @api.send(:client, :ecs, "us-east-1")
    end

    test "a call answers the SDK's response as a hash" do
      stub_client(:ecs, list_clusters: { cluster_arns: [ "arn:aws:ecs:eu-west-1:123456789012:cluster/prod" ] })

      assert_equal({ cluster_arns: [ "arn:aws:ecs:eu-west-1:123456789012:cluster/prod" ] }, @api.call(:ecs, "eu-west-1", :list_clusters))
    end

    test "every page is read up to the most asked for, and whether more were left is said" do
      pages = [ { functions: [ { function_name: "one" } ], next_marker: "2" }, { functions: [ { function_name: "two" } ], next_marker: "3" },
                { functions: [ { function_name: "three" } ] } ]
      stub_client(:lambda, list_functions: pages.deep_dup)

      rows, more = @api.all(:lambda, "eu-west-1", :list_functions, {}, :functions, max_pages: 2)
      assert_equal [ %w[one two], true ], [ rows.map { |row| row[:function_name] }, more ]

      stub_client(:lambda, list_functions: pages.deep_dup)
      rows, more = @api.all(:lambda, "eu-west-1", :list_functions, {}, :functions)
      assert_equal [ 3, false ], [ rows.size, more ]
    end

    test "AWS's refusals are raised with its own words, by kind" do
      { "AccessDeniedException" => AwsApi::Denied, "UnrecognizedClientException" => AwsApi::Denied, "ThrottlingException" => AwsApi::RateLimited,
        "ServiceNotFoundException" => AwsApi::NotFound, "InvalidParameterException" => AwsApi::Error }.each do |code, kind|
        @api = AwsApi.new(access_key_id: "AKIAEXAMPLE", secret_access_key: "secret")
        stub_client(:ecs, describe_services: code)

        error = assert_raises(kind) { @api.call(:ecs, "eu-west-1", :describe_services, services: [ "web" ]) }

        assert_match "AWS answered #{code}", error.message
        assert_kind_of Integrations::Error, error
      end
    end

    test "a region is known by its code in any partition, and its partition is read from it" do
      assert AwsApi.region?("eu-west-1")
      assert AwsApi.region?("cn-north-1")
      assert_not AwsApi.region?("europe-west1")
      assert_equal "aws", AwsApi.partition_of("us-east-1")
      assert_equal "aws-cn", AwsApi.partition_of("cn-north-1")
      assert_equal "aws-us-gov", AwsApi.partition_of("us-gov-west-1")
      assert_nil AwsApi.partition_of("nowhere-1")
    end

    private

    def stub_client(service, responses)
      gem_name, class_name = AwsApi::CLIENTS.fetch(service)
      require gem_name
      client = class_name.constantize.new(stub_responses: responses, region: "eu-west-1", credentials: ::Aws::Credentials.new("a", "b"))
      @api.stubs(:client).returns(client)
    end
  end
end
