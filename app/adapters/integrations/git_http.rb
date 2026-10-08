module Integrations
  # Git's smart HTTP passed on to a code host with the connection's own credential (CodeReading::Remote), the request
  # body and the answer both streamed through as they come. Yields :start with the status and the answer's headers,
  # then :chunk with each piece of the answer.
  module GitHttp
    class Error < Integrations::Error; end

    PASSED_REQUEST = %w[Content-Type Accept Git-Protocol Content-Encoding User-Agent].freeze
    PASSED_RESPONSE = %w[content-type cache-control].freeze
    READ_TIMEOUT = 300

    def self.forward(remote, repository, path, method:, headers:, body: nil, length: nil)
      uri = URI.parse("#{remote.url(repository)}/#{path}")
      request = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
      request.basic_auth(remote.user, remote.token.call.to_s)
      PASSED_REQUEST.each { |name| request[name] = headers[name] if headers[name].present? }
      if body
        request.body_stream = body
        length ? request.content_length = length : request["Transfer-Encoding"] = "chunked"
      end
      Http.request(uri, request, error_class: Error, read_timeout: READ_TIMEOUT) do |response|
        yield :start, response.code.to_i, response.to_hash.slice(*PASSED_RESPONSE).transform_values { |values| values.join(", ") }
        response.read_body { |chunk| yield :chunk, chunk }
      end
    end
  end
end
