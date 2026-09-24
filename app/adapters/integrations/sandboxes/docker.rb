module Integrations
  module Sandboxes
    # Boxes as containers on a Docker daemon, for development, tests and self-hosted installs. It speaks the Docker
    # Engine API over the daemon's socket, so the app image needs no docker command. A box joins SANDBOX_DOCKER_NETWORK
    # and is reached by name when the app runs in a container on that network, and is published on the host's
    # loopback otherwise.
    class Docker
      LABEL = "firefight.sandbox".freeze
      PORT = "8080/tcp".freeze
      API_VERSION = "v1.43".freeze
      DEFAULT_SOCKET = "/var/run/docker.sock".freeze

      def start(name:)
        key = SecureRandom.hex(32)
        created = request(Net::HTTP::Post, "/containers/create?#{{ name: name }.to_query}", {
          Image: Sandboxes.image, Env: [ "SANDBOX_KEY=#{key}" ], Labels: { LABEL => "1" }, ExposedPorts: { PORT => {} },
          HostConfig: {
            NetworkMode: network, PortBindings: network ? {} : { PORT => [ { HostIp: "127.0.0.1", HostPort: "" } ] },
            NanoCpus: (Float(ENV["SANDBOX_CPUS"].presence || "2") * 1_000_000_000).to_i,
            Memory: memory_bytes, AutoRemove: false
          }.compact
        })
        ref = created.fetch("Id")
        request(Net::HTTP::Post, "/containers/#{ref}/start")
        Box.new(ref: ref, address: address(ref, name), key: key)
      end

      def stop(ref)
        request(Net::HTTP::Delete, "/containers/#{ref}?force=true")
      rescue Error => error
        raise unless error.message.include?("404")
      end

      def running
        filters = { label: [ "#{LABEL}=1" ] }.to_json
        request(Net::HTTP::Get, "/containers/json?#{{ filters: filters }.to_query}").map do |container|
          Running.new(ref: container["Id"], started_at: Time.zone.at(container["Created"].to_i))
        end
      end

      private

      def network = ENV["SANDBOX_DOCKER_NETWORK"].presence

      def memory_bytes
        text = (ENV["SANDBOX_MEMORY"].presence || "4g").downcase
        number = text.to_f
        multiplier = { "g" => 1024**3, "m" => 1024**2, "k" => 1024 }.fetch(text[-1], 1)
        (number * multiplier).to_i
      end

      def address(ref, name)
        return "http://#{name}:#{PORT.to_i}" if network

        binding = request(Net::HTTP::Get, "/containers/#{ref}/json").dig("NetworkSettings", "Ports", PORT, 0)
        raise Error, "Docker published no port for the code sandbox." unless binding

        "http://#{binding['HostIp']}:#{binding['HostPort']}"
      end

      def socket_path = ENV["DOCKER_HOST"].to_s.delete_prefix("unix://").presence || DEFAULT_SOCKET

      # HTTP over the daemon's unix socket, one connection per request so nothing is left half read.
      def request(verb, path, payload = nil)
        http_request = verb.new("/#{API_VERSION}#{path}")
        http_request["Host"] = "docker"
        http_request["Connection"] = "close"
        if payload
          http_request["Content-Type"] = "application/json"
          http_request.body = payload.to_json
        end
        response = UNIXSocket.open(socket_path) do |socket|
          io = Net::BufferedIO.new(socket)
          http_request.exec(io, "1.1", http_request.path)
          Net::HTTPResponse.read_new(io).tap { |read| read.reading_body(io, http_request.response_body_permitted?) { } }
        end
        parse(response)
      rescue Errno::ENOENT, Errno::EACCES, Errno::ECONNREFUSED => error
        raise Error, "SANDBOX_PROVIDER is docker, but the Docker daemon at #{socket_path} cannot be reached (#{error.class.name.demodulize})."
      end

      def parse(response)
        body = response.body.to_s.empty? ? {} : JSON.parse(response.body)
        raise Error, "Docker #{response.code}: #{body['message']}" unless response.code.to_i.between?(200, 299)

        body
      rescue JSON::ParserError
        raise Error, "Docker answered with something that is not JSON (HTTP #{response.code})."
      end
    end
  end
end
