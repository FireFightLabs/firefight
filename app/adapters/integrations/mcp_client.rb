module Integrations
  # Streamable-HTTP MCP client for consuming external MCP servers. Servers
  # like GitHub's are session-based: initialize returns an Mcp-Session-Id
  # that every later request must echo, and the spec requires a
  # notifications/initialized before other calls. Handles plain JSON and
  # single-event SSE bodies.
  class McpClient
    class Error < Integrations::Error; end

    PROTOCOL_VERSION = "2025-06-18".freeze
    READ_TIMEOUT = 30

    def initialize(server_url:, headers: {})
      @server_url = server_url
      @headers = headers
      @session_id = nil
      @initialized = false
      @id = 0
    end

    def ping
      ensure_initialized
      true
    end

    def tools_list
      ensure_initialized
      request("tools/list").fetch("tools", [])
    end

    def call_tool(name:, arguments:)
      ensure_initialized
      request("tools/call", { name: name, arguments: arguments })
    end

    private

    def ensure_initialized
      return if @initialized

      result = request("initialize", {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: { name: "firefight", version: "1.0" }
      })
      notify("notifications/initialized")
      @initialized = true
      result
    end

    def request(method, params = {})
      response = post({ jsonrpc: "2.0", id: (@id += 1), method: method, params: params })
      capture_session(response)
      raise Error, "MCP server returned HTTP #{response.code}" unless success?(response)

      body = parse_body(response)
      raise Error, "MCP error: #{body.dig('error', 'message') || 'unknown error'}" if body["error"]

      body.fetch("result", {})
    end

    # Notifications have no id and expect no result body (202 Accepted).
    def notify(method)
      response = post({ jsonrpc: "2.0", method: method })
      capture_session(response)
    end

    def post(payload)
      uri = URI.parse(@server_url.to_s)
      raise Error, "invalid MCP server URL" unless uri.is_a?(URI::HTTP)

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json, text/event-stream"
      req["MCP-Protocol-Version"] = PROTOCOL_VERSION
      req["Mcp-Session-Id"] = @session_id if @session_id
      @headers.each { |key, value| req[key] = value }
      req.body = payload.to_json

      Http.request(uri, req, error_class: Error, read_timeout: READ_TIMEOUT)
    end

    def capture_session(response)
      session = response["Mcp-Session-Id"]
      @session_id = session if session.present?
    end

    def success?(response)
      response.code.to_i.between?(200, 299)
    end

    def parse_body(response)
      body = response.body.to_s
      return {} if body.empty?

      if response["Content-Type"].to_s.include?("text/event-stream")
        data = body.lines.find { |line| line.start_with?("data:") }
        raise Error, "empty SSE response" unless data

        JSON.parse(data.delete_prefix("data:").strip)
      else
        JSON.parse(body)
      end
    rescue JSON::ParserError
      raise Error, "server returned invalid JSON"
    end
  end
end
