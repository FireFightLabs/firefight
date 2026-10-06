module Integrations
  module MapEventSources
    # AWS's changes, read two ways on the same connection.
    #
    # Every connection reads CloudTrail's event history in each of its regions every five minutes (LookupEvents,
    # docs.aws.amazon.com/awscloudtrail/latest/APIReference/API_LookupEvents.html), which needs cloudtrail:LookupEvents and
    # no trail. AWS allows two lookups a second per account and region and answers newest first, at most 50 a page.
    # CloudTrail delivers an event about five minutes after the call on average, without a guarantee (CloudTrail user
    # guide, How CloudTrail works), so each read starts LAG before the last one ended and a repeat is dropped by its id.
    #
    # A person may also create Firefight's CloudFormation stack in a region (aws_live_updates.json, through a quick-create
    # link, docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-console-create-stacks-quick-create-links.html). Its
    # EventBridge rules send EC2, ECS and RDS state changes, the same API calls as "AWS API Call via CloudTrail" events,
    # and the stack's own status to an API destination at the connection's address, with Firefight's key for the
    # connection in the x-firefight-key header (the connection's API_KEY authorization). An API call read both ways is
    # one change, since both carry CloudTrail's eventID. Lambda sends EventBridge no state changes of its own, so its
    # functions follow their API calls only. API calls reach EventBridge only while the account has a trail logging
    # (docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-event-cloudtrail.html), and the state changes do
    # without one.
    class Aws < MapEventSource
      KEY_HEADER = "x-firefight-key".freeze
      # Where whoever runs Firefight published aws_live_updates.json. A quick-create link takes a template only from an S3
      # bucket, in one of the address forms the quick-create guide lists.
      TEMPLATE_URL = "INTEGRATION_AWS_LIVE_UPDATES_TEMPLATE_URL".freeze
      TEMPLATE_FILE = Rails.root.join("app/services/integrations/map_event_sources/aws_live_updates.json")
      S3_TEMPLATE = %r{\Ahttps://(s3[.-][a-z0-9-]+\.amazonaws\.com/[^/]+/.+|[a-z0-9.-]+\.s3\.([a-z0-9-]+\.)?amazonaws\.com/.+)\z}
      STACK_PREFIX = "firefight-live-updates".freeze
      # The commercial regions where an API destination reaches a public address, from EventBridge's user guide (API
      # destinations as targets, Region availability). Elsewhere the stack cannot be made.
      API_DESTINATION_REGIONS = %w[
        us-east-1 us-east-2 us-west-1 us-west-2 af-south-1 ap-east-1 ap-northeast-1 ap-northeast-2 ap-northeast-3 ap-south-1 ap-south-2
        ap-southeast-1 ap-southeast-2 ap-southeast-3 ca-central-1 eu-central-1 eu-central-2 eu-north-1 eu-south-1 eu-south-2 eu-west-1 eu-west-2
        eu-west-3 me-central-1 me-south-1 sa-east-1
      ].freeze
      NO_API_DESTINATIONS = "AWS does not offer EventBridge API destinations in this region, so its changes arrive from CloudTrail every five minutes.".freeze

      LAG = 15.minutes
      # LookupEvents' largest page, and how many pages one read takes before a busy region is swept instead.
      PAGE = 50
      MAX_PAGES = 20
      # Two lookups a second per account and region.
      LOOKUP_INTERVAL = 0.5
      # Only calls that changed something (LookupAttribute ReadOnly). One attribute per lookup is allowed, so the services
      # are told apart here.
      WRITES = { attribute_key: "ReadOnly", attribute_value: "false" }.freeze

      ECS = "ecs.amazonaws.com".freeze
      LAMBDA = "lambda.amazonaws.com".freeze
      EC2 = "ec2.amazonaws.com".freeze
      RDS = "rds.amazonaws.com".freeze
      # The calls that change what the map shows of each kind, by the name CloudTrail records. Lambda's carry a date and
      # version, such as UpdateFunctionCode20150331v2 (Lambda developer guide, Logging AWS Lambda API calls using AWS
      # CloudTrail), which LAMBDA_VERSION takes off. aws_live_updates.json asks EventBridge for the same calls.
      CALLS = {
        EC2 => %w[RunInstances StartInstances StopInstances TerminateInstances ModifyInstanceAttribute CreateTags DeleteTags],
        ECS => %w[CreateService UpdateService DeleteService TagResource UntagResource],
        LAMBDA => %w[CreateFunction UpdateFunctionCode UpdateFunctionConfiguration DeleteFunction TagResource UntagResource],
        RDS => %w[CreateDBInstance CreateDBInstanceReadReplica RestoreDBInstanceFromDBSnapshot RestoreDBInstanceToPointInTime
                  ModifyDBInstance RebootDBInstance StartDBInstance StopDBInstance PromoteReadReplica DeleteDBInstance
                  AddTagsToResource RemoveTagsFromResource]
      }.freeze
      LAMBDA_VERSION = /\d{8}(v\d+)?\z/
      ADDING = %w[RunInstances CreateService CreateFunction CreateDBInstance CreateDBInstanceReadReplica RestoreDBInstanceFromDBSnapshot
                  RestoreDBInstanceToPointInTime].freeze
      REMOVING = %w[TerminateInstances DeleteService DeleteFunction DeleteDBInstance].freeze

      API_CALL = "AWS API Call via CloudTrail".freeze
      EC2_STATE = "EC2 Instance State-change Notification".freeze
      # ECS Service Action and ECS Deployment State Change name the service in resources (ECS developer guide, Amazon
      # ECS service action events and service deployment state change events).
      ECS_SERVICE = [ "ECS Service Action", "ECS Deployment State Change" ].freeze
      RDS_INSTANCE = "RDS DB Instance Event".freeze
      STACK_STATUS = "CloudFormation Stack Status Change".freeze
      # The first status of a stack being deleted, sent while its rules still exist (CloudFormation user guide, Stack
      # Status Change event detail).
      STACK_DELETING = "DELETE_IN_PROGRESS".freeze

      DENIED = "Live updates need cloudtrail:LookupEvents on these keys to read CloudTrail's event history".freeze
      UNPUBLISHED = "Firefight's CloudFormation template is not published on this Firefight, so changes arrive from CloudTrail every five minutes.".freeze

      class << self
        # The key is compared as digests, so the comparison takes as long whatever was sent.
        def verify(raw_body:, headers:, secret:)
          return false if secret.blank?

          ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.digest(headers[KEY_HEADER].to_s), Digest::SHA256.digest(secret))
        end

        def events(payload, headers:)
          detail = payload["detail"].is_a?(Hash) ? payload["detail"] : {}
          case payload["detail-type"]
          when API_CALL then record_events(detail)
          when EC2_STATE
            terminated = detail["state"] == "terminated"
            state_event(payload, Packs::Aws::INSTANCE, instance_arn(payload["region"], payload["account"], detail["instance-id"]), terminated)
          when *ECS_SERVICE then state_event(payload, Packs::Aws::SERVICE, Array(payload["resources"]).first, false)
          when RDS_INSTANCE
            detail["SourceType"] == "DB_INSTANCE" ? state_event(payload, Packs::Aws::DATABASE, detail["SourceArn"].presence || Array(payload["resources"]).first, false) : []
          else []
          end
        end

        # Reads every connected region's history from where the last read ended. A region read for the first time starts
        # now. One AWS asked to slow down keeps its place and is read again next time, and a region too busy to read in
        # MAX_PAGES is swept in full.
        def poll(row, since:)
          now = Time.current
          places = cursors_of(since).slice(*regions(row))
          api = api(row)
          found = []
          regions(row).each do |region|
            from = places[region]&.then { |stamp| Time.iso8601(stamp) }
            if from
              records, complete = lookup(api, region, from - LAG, now)
              found.concat(records.flat_map { |record| record_events(record) })
              found << busy(region, now) unless complete
            end
            places[region] = now.utc.iso8601(6)
          rescue RateLimited
            next
          rescue AwsApi::Denied => error
            raise Integrations::Error, Sentence.all(DENIED, error)
          end
          MapEventSource::Polled.new(events: found, cursor: places.to_json)
        end

        # Each region the connection reads, where a person may create the stack.
        def offers(row)
          labels = IntegrationProvider.find(Packs::Aws::PROVIDER_KEY)&.connect_fields&.find { |field| field.key == Packs::Aws::REGIONS }&.options.to_a
          regions(row).map do |region|
            MapEventSource::Offer.new(place: region, label: labels.find { |option| option.value == region }&.label || region,
                                      unavailable: (NO_API_DESTINATIONS unless API_DESTINATION_REGIONS.include?(region)))
          end
        end

        def offer_words = "CloudTrail is read every five minutes. To get changes as they happen, create Firefight's CloudFormation stack in each region. " \
                          "It sends changes to EC2 instances, ECS services, Lambda functions and RDS databases to this connection. Lambda's arrive only " \
                          "while the account has a CloudTrail trail logging."

        def offer_action = "Create stack"

        def offer_unavailable_reason = (UNPUBLISHED unless template_url)

        # The quick-create link for the region, with the connection's address and key filled in. A NoEcho parameter
        # cannot be filled in from a link, so the key is a plain parameter of the stack.
        def offer_link(row, place:, url:, secret:)
          query = { templateURL: template_url, stackName: stack_name(row), param_Address: url, param_Key: secret }
          "https://#{place}.console.aws.amazon.com/cloudformation/home?region=#{place}#/stacks/create/review?" +
            query.map { |key, value| "#{key}=#{ERB::Util.url_encode(value)}" }.join("&")
        end

        def delivery_place(payload) = payload["region"].presence

        def delivery_ends?(payload)
          payload["detail-type"] == STACK_STATUS && payload.dig("detail", "status-details", "status") == STACK_DELETING
        end

        def removal_words(row, places)
          where = places.any? ? " in #{places.to_sentence}" : " in each region you created it in"
          "To stop, delete the CloudFormation stack #{stack_name(row)}#{where}. Firefight did not create it, so it cannot remove it."
        end

        def stack_name(row) = "#{STACK_PREFIX}-#{Digest::SHA256.hexdigest(row.id.to_s).first(8)}"

        def template = JSON.parse(File.read(TEMPLATE_FILE))

        # The scopes one CloudTrail record names, each with the record's eventID, or eventID and the resource when it
        # names several, so the same call read from the event history or sent by EventBridge is one change. A call that
        # failed changed nothing.
        def record_events(record)
          source = record["eventSource"].to_s
          name = record["eventName"].to_s
          name = name.sub(LAMBDA_VERSION, "") if source == LAMBDA
          return [] if record["errorCode"].present? || CALLS[source]&.include?(name) != true

          at = happened_at(record["eventTime"])
          kind, arns = named_by(source, name, record)
          arns = arns.compact.uniq
          action = action_of(name)
          arns.map do |arn|
            id = arns.one? ? record["eventID"] : "#{record['eventID']} #{arn}"
            ResourceMap::Event.new(id: id, at: at, action: action, scope: ResourceMap::Scope.new(account: record["recipientAccountId"], kind: kind, external_id: arn))
          end
        end

        # A page at a time, no faster than AWS allows, until the window is read or MAX_PAGES are.
        def lookup(api, region, from, to)
          records = []
          token = nil
          MAX_PAGES.times do |page|
            pause(LOOKUP_INTERVAL) if page.positive?
            answer = api.call(:cloudtrail, region, :lookup_events,
                              { start_time: from, end_time: to, lookup_attributes: [ WRITES ], max_results: PAGE, next_token: token }.compact)
            Array(answer[:events]).each do |event|
              next unless CALLS.key?(event[:event_source])

              record = JSON.parse(event[:cloud_trail_event].to_s)
              records << record if record.is_a?(Hash)
            rescue JSON::ParserError
              next
            end
            token = answer[:next_token]
            return [ records, true ] if token.blank?
          end
          [ records, false ]
        end

        def pause(seconds) = sleep(seconds)

        private

        def named_by(source, name, record)
          asked = record["requestParameters"].is_a?(Hash) ? record["requestParameters"] : {}
          answered = record["responseElements"].is_a?(Hash) ? record["responseElements"] : {}
          region = record["awsRegion"]
          account = record["recipientAccountId"]
          case source
          when EC2 then [ Packs::Aws::INSTANCE, instance_ids(name, asked, answered).map { |id| instance_arn(region, account, id) } ]
          when ECS then [ Packs::Aws::SERVICE, [ service_arn(name, asked, answered, region, account) ] ]
          when LAMBDA then [ Packs::Aws::FUNCTION, [ function_arn(name, asked, answered, region, account) ] ]
          else [ Packs::Aws::DATABASE, database_arns(name, asked, answered, region, account) ]
          end
        end

        # RunInstances answers the instances it started, the other instance calls name theirs in instancesSet, and tags
        # name resources of every type, of which an instance's id starts i-.
        def instance_ids(name, asked, answered)
          items = ->(set) { Array(set.is_a?(Hash) ? set["items"] : nil) }
          case name
          when "RunInstances" then items.call(answered["instancesSet"]).map { |item| item["instanceId"] }
          when "ModifyInstanceAttribute" then [ asked["instanceId"] ]
          when "CreateTags", "DeleteTags" then items.call(asked["resourcesSet"]).map { |item| item["resourceId"] }.select { |id| id.to_s.start_with?("i-") }
          else items.call(asked["instancesSet"]).map { |item| item["instanceId"] }
          end.compact
        end

        def instance_arn(region, account, id)
          "arn:#{Packs::Aws::PARTITION}:ec2:#{region}:#{account}:instance/#{id}" if region.present? && account.present? && id.present?
        end

        # The service's ARN as ECS answered it, or as the request named it, in the form with its cluster (cluster
        # "default" when none is named, as the ECS API reference says for CreateService and UpdateService).
        def service_arn(name, asked, answered, region, account)
          return (asked["resourceArn"] if asked["resourceArn"].to_s.include?(":service/")) if name.end_with?("TagResource")

          given = answered.dig("service", "serviceArn").presence || asked["service"].presence || asked["serviceName"].presence
          return given if given.to_s.start_with?("arn:")
          return unless given

          cluster = asked["cluster"].to_s.split("/").last.presence || "default"
          "arn:#{Packs::Aws::PARTITION}:ecs:#{region}:#{account}:service/#{cluster}/#{given}"
        end

        # A function by the ARN Lambda answered or the name or ARN the request gave, without a version or alias.
        def function_arn(name, asked, answered, region, account)
          given = name.end_with?("TagResource") ? asked["resource"] : answered["functionArn"].presence || asked["functionName"]
          return if given.blank?
          return given.split(":").first(7).join(":") if given.start_with?("arn:")

          "arn:#{Packs::Aws::PARTITION}:lambda:#{region}:#{account}:function:#{given}" unless given.include?(":")
        end

        # RDS keeps an identifier in lowercase. Renaming a database names both, the old one to be found gone.
        def database_arns(name, asked, answered, region, account)
          return [ (asked["resourceName"] if asked["resourceName"].to_s.include?(":db:")) ] if name.end_with?("TagsToResource", "TagsFromResource")

          named = ->(identifier) { "arn:#{Packs::Aws::PARTITION}:rds:#{region}:#{account}:db:#{identifier.downcase}" if identifier.present? }
          [ answered["dBInstanceArn"].presence || named.call(asked["dBInstanceIdentifier"]), named.call(asked["newDBInstanceIdentifier"]) ]
        end

        def action_of(name)
          return ResourceMap::Event::REMOVED if REMOVING.include?(name)
          return ResourceMap::Event::ADDED if ADDING.include?(name)

          ResourceMap::Event::UPDATED
        end

        def state_event(payload, kind, arn, removed)
          return [] if arn.blank?

          action = removed ? ResourceMap::Event::REMOVED : ResourceMap::Event::UPDATED
          [ ResourceMap::Event.new(id: payload["id"], at: happened_at(payload["time"]), action: action,
                                   scope: ResourceMap::Scope.new(account: payload["account"], kind: kind, external_id: arn)) ]
        end

        # A region whose history held more than one read takes, which a sweep reads in full instead.
        def busy(region, now)
          ResourceMap::Event.new(id: "cloudtrail-busy #{region} #{now.utc.iso8601(6)}", at: now, action: ResourceMap::Event::UPDATED, scope: ResourceMap::Scope.everything)
        end

        def cursors_of(since)
          parsed = since.present? ? JSON.parse(since) : {}
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end

        def happened_at(stamp)
          Time.iso8601(stamp.to_s)
        rescue ArgumentError
          Time.current
        end

        def template_url = ENV[TEMPLATE_URL].presence&.then { |url| url if url.match?(S3_TEMPLATE) }

        def regions(row) = Array(ConnectionSettings.of(row).field(Packs::Aws::REGIONS))

        def api(row)
          settings = ConnectionSettings.of(row)
          key = settings.credential(Packs::Aws::ACCESS_KEY_ID)
          secret = settings.credential(Packs::Aws::SECRET_ACCESS_KEY)
          raise Integrations::Error, "This connection has no AWS access key. Reconnect it on the Integrations page." if key.blank? || secret.blank?

          AwsApi.new(access_key_id: key, secret_access_key: secret)
        end
      end
    end
  end
end
