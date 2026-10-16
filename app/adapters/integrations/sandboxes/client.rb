module Integrations
  module Sandboxes
    # Talks to the command service inside one box. Every request carries the box's own key.
    class Client
      # A command runs against the repository's objects, in a read-only checkout of a commit, or in a writable copy.
      IN_GIT = "git".freeze
      IN_CHECKOUT = "checkout".freeze
      IN_COPY = "run".freeze
      IN_TERMINAL = "terminal".freeze
      IN_BROWSER = "browser".freeze
      # Replaced by the commit a ref resolves to, so git reads exactly what the heading says.
      COMMIT = "{commit}".freeze

      READY_TIMEOUT = 180
      # How long the box may take on top of the command's own time limit.
      MARGIN = 30
      # How often a command running in the background is read, and how many reads in a row may fail before it is given up.
      # The first read comes after FIRST_POLL and the wait doubles up to POLL_EVERY, so a quick command is not held up by
      # the pace a long one is read at.
      POLL_EVERY = 2
      FIRST_POLL = 0.2
      MISSES_ALLOWED = 5
      # Packing or unpacking a prepared copy, which can hold every dependency a repository installs.
      ARCHIVE_TIMEOUT = 20 * 60
      # What a background run does, beside a command.
      RUN_PREPARE = "prepare".freeze
      QUIET = ->(_progress) { }

      def initialize(box)
        @box = box
      end

      # Boxes take a few seconds to boot, and a provider can report one started before its service listens, or before it
      # has even pulled the image, so the provider says how long its box may take (Provider#ready_within). A box that
      # never answers is reported with why its last health check failed. A stop ends the wait (StopSignal).
      def wait_until_ready!(within: READY_TIMEOUT)
        deadline = within.seconds.from_now
        loop do
          failure = health_failure
          return if failure.nil?
          raise Error, Sentence.join("The code sandbox did not come up within #{within.to_i} seconds", failure) if Time.current > deadline

          pause(1)
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
      # A box that can run commands in the background follows every one there, since a proxy in front of a box may end a
      # request that waits on a long one, and a stop (StopSignal) can only end a command it follows.
      def exec(repository:, argv:, ref: nil, where: IN_CHECKOUT, timeout: 60, services: nil, on_output: nil, stdin: nil, setup: nil)
        payload = { repo: repository, ref: ref, argv: argv, where: where, timeout: timeout, services: services, stdin: stdin, setup: setup }.compact
        return send_json(Net::HTTP::Post, "/exec", payload: payload, read_timeout: timeout + MARGIN) unless runs_in_background?

        follow(send_json(Net::HTTP::Post, "/runs", payload: payload)["id"], deadline: clock + timeout + MARGIN, on_output: on_output || QUIET)
      end

      # Whether the box's image can run a command in the background. An older one answers health without saying so.
      def runs_in_background? = health["runs"] == true

      # Each installer and each of the setup's commands may take up to the box's limit for one command.
      def prepare(repository:, ref: nil, setup: nil)
        steps = 1 + Array(setup&.dig(:commands) || setup&.dig("commands")).size
        limit = (steps * 20.minutes.to_i) + MARGIN
        payload = { repo: repository, ref: ref, setup: setup }.compact
        return send_json(Net::HTTP::Post, "/prepare", payload: payload, read_timeout: limit) unless health["prepare_runs"] == true

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
        signed(request)
        Http.request(uri, request, error_class: Error, read_timeout: ARCHIVE_TIMEOUT) do |response|
          refuse_redirect!(response)
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
        signed(request)
        request["Content-Type"] = "application/gzip"
        File.open(path, "rb") do |file|
          request["Content-Length"] = file.size.to_s
          request.body_stream = file
          response = Http.request(uri, request, error_class: Error, read_timeout: ARCHIVE_TIMEOUT)
          refuse_redirect!(response)
          parsed = JSON.parse(response.body.to_s)
          raise Error, parsed["error"].to_s if response.code.to_i != 200

          parsed
        end
      rescue JSON::ParserError
        raise Error, "The code sandbox answered with something that is not JSON."
      end

      # Whether the box's image has Halon's terminal. An older one answers health without saying so.
      def terminal?
        @terminal = send_json(Net::HTTP::Get, "/health", read_timeout: 5)["terminal"] == true if @terminal.nil?
        @terminal
      rescue Error
        false
      end

      # A command in the terminal's own folder, with no repository. env is what it is handed beyond the image's own
      # settings, such as the address and token it reaches Firefight with.
      def terminal(argv:, env: {}, timeout: 60, on_output: nil)
        exec_or_follow({ where: IN_TERMINAL, argv: argv, env: env, timeout: timeout }, timeout: timeout, on_output: on_output)
      end

      # Whether the box's image has Halon's browser, read once.
      def browser?
        @browser = send_json(Net::HTTP::Get, "/health", read_timeout: 5)["browser"] == true if @browser.nil?
        @browser
      rescue Error
        false
      end

      # One check in Halon's browser, which runs as a user of its own. spec is handed to it as its input and never
      # written to the box's disk, since it may hold a saved login's password.
      def browse(spec:, timeout:, on_output: nil)
        exec_or_follow({ where: IN_BROWSER, argv: [], timeout: timeout, stdin: spec }, timeout: timeout, on_output: on_output)
      end

      # A file a terminal command reads, under the terminal's results folder.
      def place_file(name, content)
        send_json(Net::HTTP::Put, "/terminal/files/#{name}", body: content.to_s, content_type: "application/octet-stream", read_timeout: 120)
      end

      # Starts services in the box by name, answering the variables that reach them.
      def start_services(names)
        send_json(Net::HTTP::Post, "/services", payload: { services: names }, read_timeout: 120)
      end

      def alive? = health_failure.nil?

      # Why the box's health check did not answer ok, or nil when it did.
      def health_failure
        send_json(Net::HTTP::Get, "/health", read_timeout: 5)["ok"] == true ? nil : "its health check did not answer ok"
      rescue Error => error
        error.message
      end

      def lsp(repository:, method:, ref: nil, path: nil, line: nil, column: nil, language: nil, query: nil)
        payload = { repo: repository, ref: ref, method: method, path: path, line: line, column: column, language: language, query: query }.compact
        send_json(Net::HTTP::Post, "/lsp", payload: payload, read_timeout: 120)
      end

      private

      def exec_or_follow(payload, timeout:, on_output:)
        return send_json(Net::HTTP::Post, "/exec", payload: payload, read_timeout: timeout + MARGIN) unless runs_in_background?

        follow(send_json(Net::HTTP::Post, "/runs", payload: payload)["id"], deadline: clock + timeout + MARGIN, on_output: on_output || QUIET)
      end

      # What the box's image can do, read once. A box that cannot be asked is taken to be one that can do none of it.
      def health
        @health ||= send_json(Net::HTTP::Get, "/health", read_timeout: 5)
      rescue Error
        {}
      end

      # The box's address with path on it. An address can carry a query of its own, such as the token a proxy in front
      # of the box asks for, which every request keeps, apart from the parameters the box sends as cookies.
      def address_of(path)
        base = URI.parse(@box.address)
        target = URI.parse(path)
        kept = address_parameters.reject { |name, _value| @box.cookies.key?(name) }
        base.dup.tap do |uri|
          uri.path = "#{base.path.to_s.chomp('/')}#{target.path}"
          uri.query = [ (URI.encode_www_form(kept) if kept.any?), target.query ].compact_blank.join("&").presence
        end
      end

      def address_parameters = URI.decode_www_form(URI.parse(@box.address).query.to_s)

      # The box's own key, and the parameters of its address it sends as cookies.
      def signed(request)
        request["Authorization"] = "Bearer #{@box.key}"
        given = address_parameters.to_h
        cookies = @box.cookies.filter_map { |parameter, cookie| "#{cookie}=#{given[parameter]}" if given[parameter].present? }
        request["Cookie"] = cookies.join("; ") if cookies.any?
      end

      # A box answers itself, so a redirect is something in front of it asking for what the request does not carry. It
      # is named by its host and path only, since its query can hold a token.
      def refuse_redirect!(response)
        return unless response.code.to_i.between?(300, 399)

        location = URI.parse(response["location"].to_s)
        to = "#{location.host}#{location.path}".presence
        raise Error, "The code sandbox's address answered #{response.code}, a redirect#{" to #{to}" if to}, rather than the sandbox itself."
      rescue URI::InvalidURIError
        raise Error, "The code sandbox's address answered #{response.code}, a redirect, rather than the sandbox itself."
      end

      # A stop (StopSignal) ends the command in the box and stops following it.
      def follow(id, deadline:, on_output:)
        offset = 0
        misses = 0
        wait = FIRST_POLL
        loop do
          StopSignal.check!
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
          next if read["more"]

          pause(wait)
          wait = [ wait * 2, POLL_EVERY ].min
        end
      rescue StopSignal::Stopped
        stop_run(id)
        raise
      end

      # A box from an image before runs could be stopped is no longer followed, and the command runs out its time there.
      def stop_run(id)
        send_json(Net::HTTP::Delete, "/runs/#{id}", read_timeout: 5) if health["stops"] == true
      rescue Error
        nil
      end

      def answer(result)
        raise Error, result["error"].to_s if result.is_a?(Hash) && result.key?("error")

        result.to_h
      end

      def pause(seconds) = StopSignal.pause(seconds)

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def send_json(verb, path, payload: nil, body: nil, content_type: "application/json", read_timeout: 30)
        uri = address_of(path)
        request = verb.new(uri)
        signed(request)
        if payload || body
          request["Content-Type"] = content_type
          request.body = body || payload.to_json
        end
        response = Http.request(uri, request, error_class: Error, read_timeout: read_timeout)
        refuse_redirect!(response)
        parsed = JSON.parse(response.body.to_s)
        raise Error, parsed["error"].to_s if response.code.to_i != 200

        parsed
      rescue JSON::ParserError
        raise Error, "The code sandbox answered with something that is not JSON (HTTP #{response&.code})."
      end
    end
  end
end
