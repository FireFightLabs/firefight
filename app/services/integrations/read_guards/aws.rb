module Integrations
  module ReadGuards
    # AWS's API is operations, not paths. A call reads when the service's own API description defines the operation and
    # AWS names it Describe, List, Get or BatchGet, so no other method of the client is ever called. Those that still
    # answer a credential are refused, each from its service's API reference.
    module Aws
      TOOL = ApiReads::TOOL
      SERVICE = "service".freeze
      OPERATION = "operation".freeze
      PARAMS = "params".freeze
      REGION = "region".freeze
      READ = /\A(Describe|List|Get|BatchGet)[A-Z]/
      # Only these reads hand nothing secret. Secrets Manager's Get reads answer a secret's value (GetSecretValue), KMS's
      # give import material, and STS's other Get reads mint credentials (GetSessionToken, GetFederationToken).
      ONLY = {
        "secretsmanager" => /\A(List|Describe)[A-Z]/,
        "kms" => /\A(List|Describe)[A-Z]/,
        "sts" => /\AGetCallerIdentity\z/
      }.freeze
      REFUSED = {
        "secretsmanager" => "Secrets Manager's reads of a secret's value are never made. Its list and descriptions name each secret without it.",
        "kms" => "Only KMS's lists and descriptions are read, since its other reads give key material or import tokens.",
        "sts" => "STS reads other than GetCallerIdentity mint credentials, so they are never made.",
        "ssm:GetParameter" => "A Parameter Store value can be a secret, so it is never read. DescribeParameters names each parameter without its value.",
        "ssm:GetParameters" => "A Parameter Store value can be a secret, so it is never read. DescribeParameters names each parameter without its value.",
        "ssm:GetParametersByPath" => "A Parameter Store value can be a secret, so it is never read. DescribeParameters names each parameter without its value.",
        "ssm:GetParameterHistory" => "A Parameter Store value can be a secret, so its history is never read. DescribeParameters names each parameter without its value.",
        "ecr:GetAuthorizationToken" => "GetAuthorizationToken answers a password for the registry, so it is never read.",
        "ecr:GetDownloadUrlForLayer" => "GetDownloadUrlForLayer answers a link that downloads the image's layer for anyone who has it, so it is never read.",
        "ec2:GetPasswordData" => "GetPasswordData answers an instance's Windows administrator password, so it is never read.",
        "apigateway:GetUsagePlanKey" => "A usage plan's key answers the API key's value, so it is never read. GetApiKeys names each key without it.",
        "apigateway:GetUsagePlanKeys" => "A usage plan's keys answer each API key's value, so they are never read. GetApiKeys names each key without it.",
        "s3:GetObject" => "An object's contents are data rather than configuration, so they are never read. ListObjectsV2 names each " \
                          "object with its size and when it changed.",
        "s3:GetObjectTorrent" => "An object's contents are data rather than configuration, so they are never read."
      }.freeze
      # An ECS container's or Lambda function's environment and an instance's user data may hold secrets, so they are read
      # as names. A presigned link (Lambda API reference, FunctionCodeLocation) works for anyone, so it is hidden too.
      HIDDEN_FIELDS = %w[environment user_data].freeze
      PRESIGNED = /X-Amz-Signature=|[?&]Signature=/
      HIDDEN = ApiReads::HIDDEN
      INCLUDE_VALUES = %w[include_value include_values].freeze

      def self.guards?(tool_name) = tool_name == TOOL

      def self.schema = nil

      def self.reads?(_tool_name, arguments)
        reading(TOOL, arguments)
        true
      rescue Refused, PolicyRefusal
        false
      end

      def self.reading(_tool_name, arguments)
        service = arguments[SERVICE].to_s.strip.downcase
        api = AwsApi.api_of(service) or raise Refused, "service must be one of #{AwsApi::SERVICES.join(', ')}."
        operation = operation_of(api, arguments[OPERATION])
        name = api.operation(operation).name
        raise PolicyRefusal, "#{name} is not a read. AWS names its reads Describe, List, Get or BatchGet, and api_read makes no other call." unless name.match?(READ)

        reason = refusal(service, name)
        raise PolicyRefusal, reason if reason

        params = arguments[PARAMS] || {}
        raise Refused, "params must be an object, the operation's input." unless params.is_a?(Hash)

        input = shaped(params, api.operation(operation).input&.shape, name)
        if INCLUDE_VALUES.any? { |key| input[key.to_sym] == true }
          raise PolicyRefusal, "An API key's value is a credential, so it is never read. Leave include_value out to read the keys by name."
        end

        arguments.merge(SERVICE => service, OPERATION => operation.to_s, PARAMS => input)
      end

      def self.refusal(service, name)
        return REFUSED.fetch(service) if ONLY.key?(service) && !name.match?(ONLY.fetch(service))

        REFUSED["#{service}:#{name}"]
      end

      # None of the reads let through answers only secrets, so fields are hidden one by one instead.
      def self.secret?(_service, _operation) = false

      def self.operation_of(api, given)
        wanted = folded(given)
        operation = api.operation_names.find { |name| folded(name) == wanted }
        raise Refused, "operation must be one of the service's operations, such as DescribeServices, as its API reference names them." unless operation

        operation
      end

      # A name as AWS writes it (TargetGroupArn) and as the SDK does (target_group_arn) folds to the same text.
      def self.folded(name) = name.to_s.strip.delete("_").downcase
      private_class_method :folded
      private_class_method :operation_of

      # A map keeps its own keys, such as a DynamoDB item's attribute names.
      def self.shaped(value, shape, operation)
        case shape
        when ::Seahorse::Model::Shapes::StructureShape
          raise Refused, "#{operation} takes an object there." unless value.is_a?(Hash)

          value.to_h do |key, inner|
            member = shape.member_names.find { |name| folded(name) == folded(key) }
            raise Refused, "#{operation} takes no #{key}. It takes #{shape.member_names.join(', ')}." unless member

            [ member, shaped(inner, shape.member(member).shape, operation) ]
          end
        when ::Seahorse::Model::Shapes::ListShape
          Array(value).map { |inner| shaped(inner, shape.member.shape, operation) }
        when ::Seahorse::Model::Shapes::MapShape
          raise Refused, "#{operation} takes an object there." unless value.is_a?(Hash)

          value.to_h { |key, inner| [ key.to_s, shaped(inner, shape.value.shape, operation) ] }
        when ::Seahorse::Model::Shapes::TimestampShape
          value.is_a?(String) ? Time.iso8601(value) : value
        when ::Seahorse::Model::Shapes::IntegerShape
          value.is_a?(String) && value.match?(/\A-?\d+\z/) ? value.to_i : value
        when ::Seahorse::Model::Shapes::BooleanShape
          value.is_a?(String) ? value == "true" : value
        else value
        end
      rescue ArgumentError
        raise Refused, "#{operation} takes a time as ISO 8601, such as 2026-10-01T10:00:00Z."
      end
      private_class_method :shaped

      def self.hidden(value)
        case value
        when Hash
          value.to_h do |key, inner|
            [ key, HIDDEN_FIELDS.include?(key.to_s) ? ApiReads.names_only(inner) : hidden(inner) ]
          end
        when Array then value.map { |inner| hidden(inner) }
        when IO, StringIO then "[a file, not shown]"
        when String then value.match?(PRESIGNED) ? HIDDEN : value
        else value
        end
      end
    end
  end
end
