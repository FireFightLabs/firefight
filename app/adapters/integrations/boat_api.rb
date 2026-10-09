module Integrations
  # boat.dev's public API (docs.boat.dev/api/v1) with the deployment's own key. A refusal is raised in boat's words as
  # the class its status names, and every one is a Sandboxes::Error, so a box boat cannot start fails over.
  class BoatApi
    NAME = "boat.dev".freeze
    ROOT = "https://boat.dev/api/v1".freeze

    class Error < Sandboxes::Error; end
    class Unauthorized < Error; end
    class Forbidden < Error; end
    class NotFound < Error
      include Integrations::NotFound
    end
    # 503 no_ready_machine, boat's answer to failFast when no machine of the size is ready. Nothing started and nothing is billed.
    class NoCapacity < Error; end

    REFUSALS = { 401 => Unauthorized, 403 => Forbidden, 404 => NotFound, 503 => NoCapacity }.freeze
    VERBS = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.freeze
    # boat's error envelope puts its words in message and its code in code (docs.boat.dev/api/v1, Error model).
    REASON = ->(body) { [ Http.words(body["message"]) || Http.words(body["error"]), body["code"].presence && "(#{body['code']})" ].compact.join(" ").presence }

    # A new sandbox, or one deployed from a named snapshot when the body says from. The idempotency key makes a retry
    # after a lost answer return the same sandbox instead of a second billable one.
    def create(body, idempotency_key:) = call(:post, "/sandboxes", body: body, headers: { "Idempotency-Key" => idempotency_key })

    def sandbox(id) = call(:get, "/sandboxes/#{segment(id)}")["sandbox"].to_h

    # Create takes no name, so a box is named once it exists.
    def rename(id, name) = call(:patch, "/sandboxes/#{segment(id)}", body: { name: name })

    # Archives the sandbox. Its machine stops, boat keeps its disk as a snapshot and bills nothing more.
    def stop(id) = call(:post, "/sandboxes/#{segment(id)}/stop")

    # Deletes the sandbox and its snapshots for good. boat asks for the id again in a header, so a delete names its target.
    def delete(id) = call(:delete, "/sandboxes/#{segment(id)}", headers: { "X-Ascii-Confirm-Delete" => id.to_s })

    # Every sandbox of the account, following pageInfo.nextCursor to the end.
    def sandboxes
      listed = []
      cursor = nil
      loop do
        page = call(:get, "/sandboxes", query: { limit: 100, cursor: cursor })
        listed.concat(page["sandboxes"].to_a)
        cursor = page.dig("pageInfo", "nextCursor")
        return listed unless page.dig("pageInfo", "hasMore") && cursor.present?
      end
    end

    # Starts a shell command in the background as the sandbox's user, answering its processId.
    def run_detached(id, command)
      call(:post, "/sandboxes/#{segment(id)}/commands", body: { command: command, detached: true })["processId"]
    end

    # A detached command's status, running or exited, its exit code and the tail of its output.
    def command_status(id, process_id) = call(:get, "/sandboxes/#{segment(id)}/commands/#{segment(process_id)}", query: { tailBytes: 4_096 })

    # The stable https address for a port inside the sandbox, gated by the _token it carries.
    def host(id, port, title:) = call(:post, "/sandboxes/#{segment(id)}/host", body: { port: port, title: title })["url"].to_s

    def save_snapshot(id, name) = call(:post, "/named-snapshots", body: { sandboxId: id, name: name })["snapshot"].to_h

    def snapshot(name) = call(:get, "/named-snapshots/#{segment(name)}")["snapshot"].to_h

    def snapshots = call(:get, "/named-snapshots")["snapshots"].to_a

    def delete_snapshot(name) = call(:delete, "/named-snapshots/#{segment(name)}")

    private

    def call(verb, path, body: nil, query: {}, headers: {})
      uri = URI.parse("#{ROOT}#{path}")
      uri.query = URI.encode_www_form(query.compact) if query.compact.any?
      request = VERBS.fetch(verb).new(uri)
      request["Authorization"] = "Bearer #{key}"
      request["Accept"] = "application/json"
      request["X-Boat-Org"] = ENV["BOAT_ORG"] if ENV["BOAT_ORG"].present?
      headers.each { |name, value| request[name] = value }
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      answer = Http.json(uri, request, error_class: Error, provider_name: NAME, reason: REASON, refine: ->(code, _said) { REFUSALS[code] }, read_timeout: 60)
      answer.is_a?(Hash) ? answer : {}
    end

    def key = ENV["BOAT_API_KEY"].presence || raise(Error, "BOAT_API_KEY is not set.")

    def segment(value) = Http.segment(value)
  end
end
