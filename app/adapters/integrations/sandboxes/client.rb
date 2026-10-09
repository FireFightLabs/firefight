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
      # How often a command running in the background is read, and how many reads in a row may fail before it is given up.
      POLL_EVERY = 2
      MISSES_ALLOWED = 5
      # Packing or unpacking a prepared copy, which can hold every dependency a repository installs.
      ARCHIVE_TIMEOUT = 20 * 60
      # What a background run does, beside a command.
      RUN_PREPARE = "prepare".freeze
      QUIET = ->(_progress) { }

      def initialize(box)
        @box = box
      end

      # Boxes take a few seconds to boot, and a provider can report one started before its service listens.
      def wait_until_ready!
        deadline = READY_TIMEOUT.seconds.from_now
        loop do
          return if alive?
          raise Error, "The code sandbox did not come up within #{READY_TIMEOUT} seconds." if Time.current > deadline

          sleep 1
        end
      end

      def push(repository, bundle)
        send_json(Net::HTTP::Put, "/repos/#{repository}", body: bundle, content_type: "application/octet-stream", read_timeout: 600)
      end

      # on_output hears what the command writes to the file the box names in SANDBOX_PROGRESS, in whole lines, while it
      # runs, and is called on every read even when there is nothing new. A box from an image before background commands
      # runs it in one request as before, and on_output never hears anything. Either way the answer is the same. stdin is
      # what the command reads, for a credential that must not show in its arguments.
      # setup is the repository's setup (services, env, commands), whose services and variables a command in the copy runs with.
      # A box reached through a proxy follows every command in the background, since a proxy may end a request that
      # waits on a long one.
      def exec(repository:, argv:, ref: nil, where: IN_CHECKOUT, timeout: 60, services: nil, on_output: nil, stdin: nil, setup: nil)
        payload = { repo: repository, ref: ref, argv: argv, where: where, timeout: timeout, services: services, stdin: stdin, setup: setup }.compact
        background = (on_output || @box.relayed) && runs_in_background?
        return send_json(Net::HTTP::Post, "/exec", payload: payload, read_timeout: timeout + MARGIN) unless background

        follow(send_json(Net::HTTP::Post, "/runs", payload: payload)["id"], deadline: clock + timeout + MARGIN, on_output: on_output || QUIET)
      end

      # Whether the box's image can run a command in the background. An older one answers health without saying so.
      def runs_in_background? = health["runs"] == true

      # Each installer and each of the setup's commands may take up to the box's limit for one command.
      def prepare(repository:, ref: nil, setup: nil)
        steps = 1 + Array(setup&.dig(:commands) || setup&.dig("commands")).size
        limit = (steps * 20.minutes.to_i) + MARGIN
        payload = { repo: repository, ref: ref, setup: setup }.compact
        return send_json(Net::HTTP::Post, "/prepare", payload: payload, read_timeout: limit) unless @box.relayed && health["prepare_runs"] == true

        follow(send_json(Net::HTTP::Post, "/runs", payload: payload.merge(action: RUN_PREPARE))["id"], deadline: clock + limit, on_output: QUIET)
      end

      # Gives the copy at ref what preparing the copy at from installed, in the same box, as a copy restored from an
      # archive starts, so preparing it runs each installer only once more.
      def seed(repository:, ref:, from:)
        send_json(Net::HTTP::Post, "/prepare/seed", payload: { repo: repository, ref: ref, from: from }, read_timeout: ARCHIVE_TIMEOUT)
      end

      # Whether the box can start a setup's services from their own images.
      def images? = health["images"] == true

      # What decides what preparing a copy at ref installs, as a digest, and whether that copy is prepared already.
      def prepare_state(repository:, ref: nil)
        send_json(Net::HTTP::Post, "/prepare/state", payload: { repo: repository, ref: ref }.compact)
      end

      # Whether the box's image takes a repository's setup and keeps what preparing installed. An older one does neither.
      def setups? = health["setups"] == true

      # What preparing the copy at ref installed, packed and written to the file at path as it arrives. Raises when it
      # is larger than limit bytes.
      def download_archive(repository:, ref:, path:, limit:)
        uri = address_of("/prepare/archive?#{{ repo: repository, ref: ref }.to_query}")
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@box.key}"
        Http.request(uri, request, error_class: Error, read_timeout: ARCHIVE_TIMEOUT) do |response|
          raise Error, "The code sandbox could not pack the prepared copy: #{response.body}" unless response.code.to_i == 200
          raise Error, "The prepared copy is larger than #{limit / 1.megabyte} MB, so it is not kept." if response["content-length"].to_i > limit

          File.open(path, "wb") do |file|
            response.read_body do |chunk|
              file.write(chunk)
              raise Error, "The prepared copy is larger than #{limit / 1.megabyte} MB, so it is not kept." if file.size > limit
            end
          end
        end
        path
      end

      # Hands the box what an earlier copy installed, from the file at path, for the copy at ref to start with.
      def upload_archive(repository:, ref:, path:)
        uri = address_of("/prepare/archive?#{{ repo: repository, ref: ref }.to_query}")
        request = Net::HTTP::Put.new(uri)
        request["Authorization"] = "Bearer #{@box.key}"
        request["Content-Type"] = "application/gzip"
        File.open(path, "rb") do |file|
          request["Content-Length"] = file.size.to_s
          request.body_stream = file
          response = Http.request(uri, request, error_class: Error, read_timeout: ARCHIVE_TIMEOUT)
          parsed = JSON.parse(response.body.to_s)
          raise Error, parsed["error"].to_s if response.code.to_i != 200

          parsed
        end
      rescue JSON::ParserError
        raise Error, "The code sandbox answered with something that is not JSON."
      end

      # Starts services in the box by name, answering the variables that reach them.
      def start_services(names)
        send_json(Net::HTTP::Post, "/services", payload: { services: names }, read_timeout: 120)
      end

      def alive?
        send_json(Net::HTTP::Get, "/health", read_timeout: 5)["ok"] == true
      rescue Error
        false
      end

      def lsp(repository:, method:, ref: nil, path: nil, line: nil, column: nil, language: nil, query: nil)
        payload = { repo: repository, ref: ref, method: method, path: path, line: line, column: column, language: language, query: query }.compact
        send_json(Net::HTTP::Post, "/lsp", payload: payload, read_timeout: 120)
      end

      private

      # What the box's image can do, read once. A box that cannot be asked is taken to be one that can do none of it.
      def health
        @health ||= send_json(Net::HTTP::Get, "/health", read_timeout: 5)
      rescue Error
        {}
      end

      # The box's address with path on it. An address can carry a query of its own, such as the token a proxy in front
      # of the box asks for, which every request keeps.
      def address_of(path)
        base = URI.parse(@box.address)
        target = URI.parse(path)
        base.dup.tap do |uri|
          uri.path = "#{base.path.to_s.chomp('/')}#{target.path}"
          uri.query = [ base.query, target.query ].compact_blank.join("&").presence
        end
      end

      def follow(id, deadline:, on_output:)
        offset = 0
        misses = 0
        loop do
          begin
            read = send_json(Net::HTTP::Get, "/runs/#{id}?after=#{offset}")
            misses = 0
          rescue Error
            misses += 1
            raise if misses > MISSES_ALLOWED

            pause(POLL_EVERY)
            next
          end
          offset = read["offset"].to_i
          on_output.call(read["progress"].to_s)
          return answer(read["result"]) if read["done"]
          raise Error, "The code sandbox did not finish the command in time." if clock > deadline

          pause(POLL_EVERY) unless read["more"]
        end
      end

      def answer(result)
        raise Error, result["error"].to_s if result.is_a?(Hash) && result.key?("error")

        result.to_h
      end

      def pause(seconds) = sleep(seconds)

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def send_json(verb, path, payload: nil, body: nil, content_type: "application/json", read_timeout: 30)
        uri = address_of(path)
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
