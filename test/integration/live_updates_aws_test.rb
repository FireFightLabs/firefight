require "test_helper"

# AWS's changes reach the map two ways on one connection: Firefight reads CloudTrail's event history every five minutes,
# and a CloudFormation stack a person creates sends them as they happen. The same change read both ways is read again once.
class LiveUpdatesAwsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include LiveUpdatesTestHelper

  Source = Integrations::MapEventSources::Aws
  ACCOUNT = "123456789012".freeze
  SERVICE_ARN = "arn:aws:ecs:eu-west-1:#{ACCOUNT}:service/prod/web".freeze
  TEMPLATE = "https://firefight-templates.s3.us-east-1.amazonaws.com/aws-live-updates.json".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Integrations::AwsApi.any_instance.stubs(:identity).returns(account: ACCOUNT, arn: "arn:aws:iam::#{ACCOUNT}:user/firefight")
    Source.stubs(:pause)
  end

  test "a change sent by the stack is read again once, and the same change read from CloudTrail is not read again" do
    row = aws_row
    with_app_host { Integrations::MapEvents.prepare!(row) }
    row.reload
    assert row.map_events_secret.present?, "Firefight makes the key the stack sends with"
    assert_equal [ true, nil ], [ row.live_updates.on, row.live_updates.reason ], "CloudTrail is read from the start"
    assert_equal [ nil, nil ], row.live_updates_offer.places.map(&:sent_at)

    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ service_found("completed") ]))
    Integrations::AwsApi.any_instance.stubs(:call).with(:ecs, "eu-west-1", :describe_services, has_entries(services: [ SERVICE_ARN ]))
                        .returns(services: [ ecs_service(running: 0) ])

    body = api_call(update_service).to_json
    post api_v1_map_events_path(row.map_events_token), params: body, headers: { Source::KEY_HEADER => "forged", "Content-Type" => "application/json" }
    assert_response :unauthorized
    post api_v1_map_events_path(row.map_events_token), params: body, headers: keyed(row)
    assert_response :ok
    assert row.reload.live_updates_offer.places.find { |place| place.place == "eu-west-1" }.sent_at.present?, "the region shows as sending"

    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert_equal "degraded", ResourceMap::Resource.find_by!(workspace: @workspace, provider: "aws", external_id: SERVICE_ARN).status

    row.update!(map_events_cursor: { "eu-west-1" => 10.minutes.ago.utc.iso8601(6), "us-east-1" => 10.minutes.ago.utc.iso8601(6) }.to_json)
    Integrations::AwsApi.any_instance.stubs(:call).with(:cloudtrail, "eu-west-1", :lookup_events, anything)
                        .returns(events: [ { event_id: "ev-1", event_source: Source::ECS, cloud_trail_event: update_service.to_json } ])
    Integrations::AwsApi.any_instance.stubs(:call).with(:cloudtrail, "us-east-1", :lookup_events, anything).returns(events: [])
    assert_no_enqueued_jobs(only: Integrations::MapEventJob) { Integrations::MapEvents.poll!(row) }
    assert_equal 1, ResourceMap::ReceivedEvent.where(integration_environment: row).count
    assert_nil row.reload.map_events_error
  end

  test "keys that may not read CloudTrail leave live updates off with the reason, unless a stack sends changes, until it is deleted" do
    row = aws_row
    with_app_host { Integrations::MapEvents.prepare!(row) }
    row.update!(map_events_cursor: { "eu-west-1" => 10.minutes.ago.utc.iso8601(6) }.to_json)
    denied = "AWS answered AccessDeniedException: User is not authorized to perform: cloudtrail:LookupEvents"
    Integrations::AwsApi.any_instance.stubs(:call).with(:cloudtrail, "eu-west-1", :lookup_events, anything).raises(Integrations::AwsApi::Denied, denied)

    Integrations::MapEvents.poll!(row)
    state = row.reload.live_updates
    assert_not state.on
    assert_equal "Firefight could not follow AWS's changes: #{Source::DENIED}. #{denied}. The map still updates at each sweep.", state.reason

    post api_v1_map_events_path(row.map_events_token), params: stack_status("us-east-1", "CREATE_COMPLETE").to_json, headers: keyed(row)
    assert_response :ok
    state = row.reload.live_updates
    assert state.on
    assert_equal "Firefight could not read AWS's change log: #{Source::DENIED}. #{denied}. Changes still arrive as they happen from us-east-1.", state.reason

    post api_v1_map_events_path(row.map_events_token), params: stack_status("us-east-1", "DELETE_IN_PROGRESS").to_json, headers: keyed(row)
    assert_not row.reload.live_updates.on
    assert_empty row.map_events_sent_from
  end

  test "an admin opens each region's quick-create link, the key never in the page, and disconnecting says to delete the stack" do
    sign_in(users(:alice))
    row = aws_row
    with_app_host { Integrations::MapEvents.prepare!(row) }
    row.reload

    with_app_host do
      with_template(nil) do
        get live_updates_setup_integration_url(row.integration, environment_row_id: row.id, place: "eu-west-1")
        assert_equal Source::UNPUBLISHED, flash[:alert]
      end

      with_template(TEMPLATE) do
        get integrations_url, headers: inertia_headers
        assert_not_includes response.body, row.map_events_secret
        offer = inertia_props["integrations"].find { |each| each["provider"] == "aws" }["environments"].sole["liveUpdates"]["offer"]
        assert_equal [ %w[eu-west-1 us-east-1], "Create stack", nil ], [ offer["places"].pluck("place"), offer["action"], offer["unavailable"] ]

        get live_updates_setup_integration_url(row.integration, environment_row_id: row.id, place: "eu-west-1")
        assert_redirected_to Source.offer_link(row, place: "eu-west-1", url: Integrations::MapEvents.url_for(row), secret: row.map_events_secret)

        get live_updates_setup_integration_url(row.integration, environment_row_id: row.id, place: "ap-south-1")
        assert_equal "AWS does not read ap-south-1.", flash[:alert]

        sign_in(users(:bob))
        get live_updates_setup_integration_url(row.integration, environment_row_id: row.id, place: "eu-west-1")
        assert_not_includes response.location.to_s, "console.aws.amazon.com", "a member cannot open the link with the key in it"
      end
    end

    sign_in(users(:alice))
    post api_v1_map_events_path(row.map_events_token), params: stack_status("eu-west-1", "CREATE_COMPLETE").to_json, headers: keyed(row)
    secret = row.map_events_secret
    delete integration_url(row.integration)
    assert_equal "AWS is disconnected and Firefight no longer accepts the changes it sends. #{Source.removal_words(row, [ 'eu-west-1' ])}", flash[:notice]

    post api_v1_map_events_path(row.map_events_token), params: stack_status("eu-west-1", "UPDATE_COMPLETE").to_json,
                                                        headers: { Source::KEY_HEADER => secret, "Content-Type" => "application/json" }
    assert_response :not_found
    assert_nil row.reload.map_events_secret
  end

  private

  def aws_row
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS", slug: "aws")
    row = integration.integration_environments.create!
    Integrations::Packs::Aws.store_credentials!(row, Integrations::Packs::Aws::ACCESS_KEY_ID => "AKIAEXAMPLE", Integrations::Packs::Aws::SECRET_ACCESS_KEY => "secret")
    row.store_fields!(Integrations::Packs::Aws::REGIONS => %w[eu-west-1 us-east-1])
    row
  end

  def keyed(row) = { Source::KEY_HEADER => row.map_events_secret, "Content-Type" => "application/json" }

  def update_service
    { "eventID" => "ev-1", "eventTime" => 2.minutes.ago.utc.iso8601, "eventSource" => Source::ECS, "eventName" => "UpdateService",
      "awsRegion" => "eu-west-1", "recipientAccountId" => ACCOUNT, "requestParameters" => { "cluster" => "prod", "service" => "web" },
      "responseElements" => { "service" => { "serviceArn" => SERVICE_ARN } } }
  end

  def api_call(record)
    { "id" => "eb-1", "detail-type" => Source::API_CALL, "source" => "aws.ecs", "account" => ACCOUNT, "time" => Time.current.utc.iso8601,
      "region" => "eu-west-1", "resources" => [], "detail" => record }
  end

  def stack_status(region, status)
    { "id" => "eb-#{region}-#{status}", "detail-type" => Source::STACK_STATUS, "source" => "aws.cloudformation", "account" => ACCOUNT,
      "time" => Time.current.utc.iso8601, "region" => region, "resources" => [],
      "detail" => { "stack-id" => "arn:aws:cloudformation:#{region}:#{ACCOUNT}:stack/firefight-live-updates", "status-details" => { "status" => status } } }
  end

  def ecs_service(running:)
    { service_arn: SERVICE_ARN, service_name: "web", cluster_arn: "arn:aws:ecs:eu-west-1:#{ACCOUNT}:cluster/prod", status: "ACTIVE",
      desired_count: 2, running_count: running, launch_type: "FARGATE", deployments: [ { status: "PRIMARY", rollout_state: "COMPLETED" } ] }
  end

  def service_found(status)
    ResourceMap::Found.new(provider: "aws", account: ACCOUNT, kind: ResourceMap::KIND_SERVICE, external_id: SERVICE_ARN, name: "web", status: status)
  end

  def sign_in(user)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(@workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end

  def with_template(url)
    previous = ENV[Source::TEMPLATE_URL]
    ENV[Source::TEMPLATE_URL] = url
    yield
  ensure
    ENV[Source::TEMPLATE_URL] = previous
  end
end
