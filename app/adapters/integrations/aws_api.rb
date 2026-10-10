require "aws-sdk-core"

module Integrations
  # Calls to AWS with a workspace's own access keys, for the AWS integration, through AWS's own SDK for Ruby. A call names
  # the service, the region and the operation as the SDK names them, and answers the SDK's response as a hash. Each
  # service's gem is loaded on its first call, so the app does not load them all at boot.
  class AwsApi
    class Error < Integrations::Error; end
    # Asked too often, so a caller making many calls stops rather than keep being refused.
    class RateLimited < Error
      include Integrations::RateLimited
    end
    # The keys are wrong, or their policy does not allow the call.
    class Denied < Error; end
    class NotFound < Error
      include Integrations::NotFound
    end

    # Each service the integration reads, by the name botocore keeps its description under, with the gem and client class
    # AWS publishes for it. Those after logs are reached only by the general read (Integrations::ApiReads).
    CLIENTS = {
      sts: [ "aws-sdk-core", "Aws::STS::Client" ],
      ecs: [ "aws-sdk-ecs", "Aws::ECS::Client" ],
      lambda: [ "aws-sdk-lambda", "Aws::Lambda::Client" ],
      ec2: [ "aws-sdk-ec2", "Aws::EC2::Client" ],
      rds: [ "aws-sdk-rds", "Aws::RDS::Client" ],
      cloudtrail: [ "aws-sdk-cloudtrail", "Aws::CloudTrail::Client" ],
      cloudwatch: [ "aws-sdk-cloudwatch", "Aws::CloudWatch::Client" ],
      logs: [ "aws-sdk-cloudwatchlogs", "Aws::CloudWatchLogs::Client" ],
      acm: [ "aws-sdk-acm", "Aws::ACM::Client" ],
      apigateway: [ "aws-sdk-apigateway", "Aws::APIGateway::Client" ],
      apigatewayv2: [ "aws-sdk-apigatewayv2", "Aws::ApiGatewayV2::Client" ],
      autoscaling: [ "aws-sdk-autoscaling", "Aws::AutoScaling::Client" ],
      cloudformation: [ "aws-sdk-cloudformation", "Aws::CloudFormation::Client" ],
      cloudfront: [ "aws-sdk-cloudfront", "Aws::CloudFront::Client" ],
      codebuild: [ "aws-sdk-codebuild", "Aws::CodeBuild::Client" ],
      codedeploy: [ "aws-sdk-codedeploy", "Aws::CodeDeploy::Client" ],
      codepipeline: [ "aws-sdk-codepipeline", "Aws::CodePipeline::Client" ],
      dynamodb: [ "aws-sdk-dynamodb", "Aws::DynamoDB::Client" ],
      ecr: [ "aws-sdk-ecr", "Aws::ECR::Client" ],
      eks: [ "aws-sdk-eks", "Aws::EKS::Client" ],
      elasticache: [ "aws-sdk-elasticache", "Aws::ElastiCache::Client" ],
      elbv2: [ "aws-sdk-elasticloadbalancingv2", "Aws::ElasticLoadBalancingV2::Client" ],
      health: [ "aws-sdk-health", "Aws::Health::Client" ],
      iam: [ "aws-sdk-iam", "Aws::IAM::Client" ],
      kms: [ "aws-sdk-kms", "Aws::KMS::Client" ],
      route53: [ "aws-sdk-route53", "Aws::Route53::Client" ],
      s3: [ "aws-sdk-s3", "Aws::S3::Client" ],
      secretsmanager: [ "aws-sdk-secretsmanager", "Aws::SecretsManager::Client" ],
      sns: [ "aws-sdk-sns", "Aws::SNS::Client" ],
      sqs: [ "aws-sdk-sqs", "Aws::SQS::Client" ],
      ssm: [ "aws-sdk-ssm", "Aws::SSM::Client" ],
      costexplorer: [ "aws-sdk-costexplorer", "Aws::CostExplorer::Client" ]
    }.freeze
    SERVICES = CLIENTS.keys.map(&:to_s).freeze
    # The error codes AWS's services answer when the keys or their policy refuse a call, and when what was named is not
    # there, from each service's API reference.
    DENIED = %w[
      AccessDenied AccessDeniedException UnauthorizedOperation UnauthorizedException UnrecognizedClientException
      InvalidClientTokenId SignatureDoesNotMatch AuthFailure ExpiredToken ExpiredTokenException IncompleteSignature
    ].freeze
    NOT_FOUND = %w[
      ResourceNotFoundException ServiceNotFoundException ClusterNotFoundException DBInstanceNotFound DBInstanceNotFoundFault
      InvalidInstanceID.NotFound
    ].freeze
    # The codes AWS's services answer when a caller is asked to slow down, such as Throttling from EC2 and RDS,
    # ThrottlingException from ECS and CloudWatch, TooManyRequestsException from Lambda, and LimitExceededException from
    # CloudWatch Logs when too many Logs Insights queries run at once.
    THROTTLED = %w[
      Throttling ThrottlingException ThrottledException RequestThrottled RequestThrottledException RequestLimitExceeded
      TooManyRequestsException LimitExceededException EC2ThrottledException
    ].freeze
    MAX_PAGES = 10
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30

    def initialize(access_key_id:, secret_access_key:)
      @access_key_id = access_key_id
      @secret_access_key = secret_access_key
      @clients = {}
    end

    # Whose keys these are: the account, the user or role, and its ARN.
    def identity(region) = call(:sts, region, :get_caller_identity)

    # The description of a service's API its client is built from (Seahorse::Model::Api), with every operation it defines
    # and each one's input, or nil for a service the integration does not reach.
    def self.api_of(service)
      gem_name, class_name = CLIENTS[service.to_s.to_sym]
      return nil unless class_name

      require gem_name
      class_name.constantize.api
    end

    def call(service, region, operation, params = {})
      answering { client(service, region).public_send(operation, params).to_h }
    end

    # Every page of a list the SDK pages through, up to max_pages, with whether more were left unread.
    def all(service, region, operation, params, key, max_pages: MAX_PAGES)
      answering do
        rows = []
        more = false
        client(service, region).public_send(operation, params).each_page.with_index do |page, index|
          rows.concat(Array(page.to_h[key]))
          next unless index + 1 >= max_pages

          more = page.next_page?
          break
        end
        [ rows, more ]
      end
    end

    private

    def answering
      yield
    rescue ::Aws::Errors::ServiceError => error
      raise kind_of_error(error), "AWS answered #{error.code}: #{error.message.presence || 'no reason given'}"
    rescue ::Aws::Errors::MissingCredentialsError, ::Aws::Errors::InvalidRegionError, ::Seahorse::Client::NetworkingError => error
      raise Error, "AWS could not be reached: #{error.message}"
    end

    def kind_of_error(error)
      return RateLimited if THROTTLED.include?(error.code.to_s)
      return Denied if DENIED.include?(error.code.to_s)
      return NotFound if NOT_FOUND.include?(error.code.to_s)

      Error
    end

    def client(service, region)
      @clients[[ service, region ]] ||= begin
        gem_name, class_name = CLIENTS.fetch(service)
        require gem_name
        class_name.constantize.new(
          region: region, credentials: ::Aws::Credentials.new(@access_key_id, @secret_access_key),
          http_open_timeout: OPEN_TIMEOUT, http_read_timeout: READ_TIMEOUT, retry_mode: "standard", max_attempts: 3
        )
      end
    end
  end
end
