module Integrations
  # Minimal Streamable-HTTP MCP client for consuming external MCP servers:
  # stateless JSON-RPC POSTs with per-environment auth headers. Handles both
  # plain JSON and single-event SSE response bodies.
  class McpClient
    class Error < StandardError; end

    PROTOCOL_VERSION = "2025-03-26".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30

    def initialize(server_url:, headers: {})
      @server_url = server_url
      @headers = headers
    end

    def ping
      initialize_session.present?
    end

    def tools_list
      initialize_session
      rpc("tools/list").fetch("tools", [])
    end

    def call_tool(name:, arguments:)
      initialize_session
      rpc("tools/call", { name: name, arguments: arguments })
    end

    private

    def initialize_session
      @initialized ||= rpc("initialize", {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: { name: "firefight", version: "1.0" }
      })
    end

    def rpc(method, params = {})
      uri = URI.parse(@server_url.to_s)
      raise Error, "invalid MCP server URL" unless uri.is_a?(URI::HTTP)

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json, text/event-stream"
      @headers.each { |key, value| request[key] = value }
      request.body = { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
      raise Error, "MCP server returned HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

      body = parse_body(response)
      raise Error, "MCP error: #{body.dig('error', 'message')}" if body["error"]

      body.fetch("result", {})
    rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError => e
      raise Error, "MCP server unreachable: #{e.class.name}"
    end

    def parse_body(response)
      body = response.body.to_s
      if response["Content-Type"].to_s.include?("text/event-stream")
        data = body.lines.find { |line| line.start_with?("data:") }
        raise Error, "empty SSE response" unless data

        JSON.parse(data.delete_prefix("data:").strip)
      else
        JSON.parse(body)
      end
    rescue JSON::ParserError
      raise Error, "MCP server returned invalid JSON"
    end
  end
end
