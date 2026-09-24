module Integrations
  module Sandboxes
    # Talks to the command service inside one box. Every request carries the box's own key.
    class Client
      # A command runs against the repository's objects, in a read-only checkout of a commit, or in a writable copy.
      IN_GIT = "git".freeze
      IN_CHECKOUT = "checkout".freeze
      IN_COPY = "run".freeze
      # Replaced by the commit a ref resolves to, so git reads exactly what the heading says.
      COMMIT = "{commit}".freeze

      READY_TIMEOUT = 180
      # How long the box may take on top of the command's own time limit.
      MARGIN = 30

      def initialize(box)
        @box = box
      end

      # Boxes take a few seconds to boot, and a provider can report one started before its service listens.
      def wait_until_ready!
        deadline = READY_TIMEOUT.seconds.from_now
        loop do
          return if ready?
          raise Error, "The code sandbox did not come up within #{READY_TIMEOUT} seconds." if Time.current > deadline

          sleep 1
        end
      end

      def push(repository, bundle)
        send_json(Net::HTTP::Put, "/repos/#{repository}", body: bundle, content_type: "application/octet-stream", read_timeout: 600)
      end

      def exec(repository:, argv:, ref: nil, where: IN_CHECKOUT, timeout: 60, services: nil)
        payload = { repo: repository, ref: ref, argv: argv, where: where, timeout: timeout, services: services }.compact
        send_json(Net::HTTP::Post, "/exec", payload: payload, read_timeout: timeout + MARGIN)
      end

      def prepare(repository:, ref: nil)
        send_json(Net::HTTP::Post, "/prepare", payload: { repo: repository, ref: ref }.compact, read_timeout: 20.minutes.to_i + MARGIN)
      end

      def lsp(repository:, method:, ref: nil, path: nil, line: nil, column: nil, language: nil, query: nil)
        payload = { repo: repository, ref: ref, method: method, path: path, line: line, column: column, language: language, query: query }.compact
        send_json(Net::HTTP::Post, "/lsp", payload: payload, read_timeout: 120)
      end

      private

      def ready?
        send_json(Net::HTTP::Get, "/health", read_timeout: 5)["ok"] == true
      rescue Error
        false
      end

      def send_json(verb, path, payload: nil, body: nil, content_type: "application/json", read_timeout: 30)
        uri = URI.parse("#{@box.address}#{path}")
        request = verb.new(uri)
        request["Authorization"] = "Bearer #{@box.key}"
        if payload || body
          request["Content-Type"] = content_type
          request.body = body || payload.to_json
        end
        response = Http.request(uri, request, error_class: Error, read_timeout: read_timeout)
        parsed = JSON.parse(response.body.to_s)
        raise Error, parsed["error"].to_s if response.code.to_i != 200

        parsed
      rescue JSON::ParserError
        raise Error, "The code sandbox answered with something that is not JSON (HTTP #{response&.code})."
      end
    end
  end
end
