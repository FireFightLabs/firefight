module Integrations
  # Calls to Upstash's Developer API (https://api.upstash.com/v2, upstash.com/docs/devops/developer-api) with a
  # connection's own Developer API key, sent as HTTP Basic with the account's email and the key, as the API's basicAuth
  # scheme says.
  class UpstashApi
    class Error < Integrations::Error; end
    # The key is wrong, or belongs to an account that cannot reach the database.
    class Refused < Error; end
    class NotFound < Error
      include Integrations::NotFound
    end

    ROOT = "https://api.upstash.com/v2".freeze
    REFUSALS = [ 401, 403 ].freeze

    # email and key are the two halves of a Developer API key as Upstash's MCP server takes it, email:API_KEY.
    def initialize(email, key)
      @authorization = "Basic #{Base64.strict_encode64("#{email}:#{key}")}"
    end

    # The database's backups (GET /redis/list-backup/{id}), each with its backup_id, name, creation_time, state and size.
    def backups(database_id) = Array(call(Net::HTTP::Get, "/redis/list-backup/#{Http.segment(database_id)}"))

    # Restores the database from one of its backups (POST /redis/restore-backup/{id} with backup_id).
    def restore_backup(database_id, backup_id) = call(Net::HTTP::Post, "/redis/restore-backup/#{Http.segment(database_id)}", { "backup_id" => backup_id })

    private

    def call(verb, path, body = nil)
      uri = URI.parse("#{ROOT}#{path}")
      request = verb.new(uri)
      request["Authorization"] = @authorization
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      Http.json(uri, request, error_class: Error, provider_name: "Upstash",
                              refine: lambda { |code, _said|
                                if REFUSALS.include?(code) then Refused
                                elsif code == 404 then NotFound
                                end
                              })
    end
  end
end
