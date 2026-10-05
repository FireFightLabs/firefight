module Integrations
  module Issues
    # What every tracker shares when it keeps an issue in step: a call that must answer, the answer read as data, and a
    # signature checked in constant time.
    module Calls
      # Words a tracker's error answer uses for an issue that is no longer there.
      MISSING = /not found|could not find|couldn't find|does not exist|doesn't exist|no longer exists|was deleted|is archived|entity not found/i

      # The tool's answer, raising Failed with the provider's words when it refused, or naming the tool when it is off.
      def run!(tool, arguments, what) = answered!(tool, call(tool, arguments, what), what)

      # An answer already had, checked the way run! checks one.
      def answered!(tool, result, what)
        raise Failed, "#{tool} is switched off for #{provider_name}, so Firefight could not #{what}. Switch it on under Integrations." if result.nil?
        raise Failed, Sentence.join("#{provider_name} refused to #{what}", Capabilities::Answers.text(result).truncate(300)) if result["isError"]

        result
      end

      # The answer as data, or Failed when it is not, since an issue Firefight cannot read is not one it can keep.
      def data!(result, what)
        data = Capabilities::Answers.data(result)
        raise Failed, "#{provider_name} answered #{what} with something that is not JSON." unless data.is_a?(Hash) || data.is_a?(Array)

        data
      end

      # The objects of a listing, a bare list or one under any of keys.
      def objects_of(data, *keys)
        list = data.is_a?(Hash) ? keys.lazy.map { |key| data[key] }.find { |found| found.is_a?(Array) } : data
        Array(list).grep(Hash)
      end

      # Whether an error answer says the issue is gone.
      def missing?(result) = result.is_a?(Hash) && result["isError"] && Capabilities::Answers.text(result).match?(MISSING)

      def self.signed?(secret, raw_body, given)
        expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body.to_s)
        given.present? && ActiveSupport::SecurityUtils.secure_compare(expected, given.to_s.downcase)
      end
    end
  end
end
