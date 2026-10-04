module Integrations
  module Packs
    # Devin for one organization, through its v3 API with a service user's key. A change is a session whose prompt
    # names the repository and the branch, the way Devin's own docs hand work over (Common flows, Hand off a task), with
    # max_acu_limit as the cost limit Devin enforces. A session is followed by its status and status_detail and the
    # pull_requests it lists, read from Devin's OpenAPI document (SessionResponse), and stopped by terminating it.
    class Devin < CodingAgent
      NAME = "Devin".freeze
      ORGANIZATION = "organization".freeze
      MAX_ACUS = "max_acus".freeze
      WHOLE_NUMBER = /\A[1-9]\d*\z/
      SERVICE_USER = "service_user".freeze

      WORKING = %w[new claimed resuming running].freeze
      # status_detail while running, from SessionResponse.
      WAITING = {
        "waiting_for_user" => "it asked a question in its session",
        "waiting_for_approval" => "it is waiting for an action to be approved in its session"
      }.freeze
      # status_detail while suspended, from SessionResponse.
      SUSPENDED = {
        "inactivity" => "Devin suspended it for inactivity",
        "user_request" => "someone suspended it",
        "usage_limit_exceeded" => "it reached its usage limit",
        "out_of_credits" => "the Devin account is out of credits",
        "out_of_quota" => "the Devin account is out of quota",
        "no_quota_allocation" => "the service user has no quota allocated",
        "payment_declined" => "Devin's payment was declined",
        "org_usage_limit_exceeded" => "the organization reached its usage limit",
        "user_usage_limit_exceeded" => "the service user reached its usage limit",
        "total_session_limit_exceeded" => "the organization reached its session limit",
        "contract_expired" => "the Devin contract expired",
        "error" => "it failed"
      }.freeze
      # The most pages of a session's messages read for its last words.
      MESSAGE_PAGES = 10

      coding_tools!

      def self.credential_fields
        [
          CredentialField.new(key: API_KEY, label: "API key", secret: true, placeholder: "cog_...",
                              hint: "A service user's API key, from Settings, Devin API, Service users in Devin. The Member role can start sessions and stop the ones that run too long.")
        ]
      end

      # Asks Devin who the key is, so a wrong key, or a service user of another organization, is said on the form. The
      # organization and the ACU limit are connect fields, whose format the registry checked already.
      def self.credential_refusal(values, region: nil, fields: {})
        key = values[API_KEY].to_s.strip
        organization = fields[ORGANIZATION].to_s
        limit = fields[MAX_ACUS].to_s
        return "Paste a Devin API key." if key.empty?
        return "Enter the organization id." if organization.empty?
        return "Enter the ACU limit as a whole number above zero, or leave it empty." unless limit.empty? || limit.match?(WHOLE_NUMBER)

        organization_refusal(DevinApi.new(key, organization).whoami, organization)
      rescue DevinApi::Error => error
        "Devin refused this key. #{error.message}"
      end

      # A service user belongs to one organization. A personal token works in every organization its owner can reach.
      def self.organization_refusal(me, organization)
        owner = me["org_id"].presence
        return if me["principal_type"] != SERVICE_USER || owner.nil? || owner == organization

        "This service user belongs to the organization #{owner}, not #{organization}."
      end

      def check_health!(environment_row)
        refusal = self.class.organization_refusal(api(environment_row).whoami, organization_of(environment_row))
        fail! refusal if refusal
      rescue DevinApi::Error => error
        fail! error.message
      end

      private

      def start(environment_row, title:, prompt:, **)
        answer = api(environment_row).create_session("prompt" => prompt, "title" => title, "max_acu_limit" => acu_limit(environment_row))
        id = answer["session_id"].presence || fail!("Devin answered without a session id.")
        Session.new(id: id, page: answer["url"].presence)
      end

      def poll(environment_row, session)
        state_of(api(environment_row).session(session.id))
      end

      def stop(environment_row, session)
        api(environment_row).terminate(session.id)
      end

      def session_for(environment_row, id)
        answer = api(environment_row).session(id)
        Session.new(id: answer["session_id"].presence || id, page: answer["url"].presence)
      end

      # Devin's last message, read once the session ended. A session whose messages cannot be read still has its pull
      # requests.
      def finished(environment_row, session, state)
        last = nil
        after = nil
        MESSAGE_PAGES.times do
          page = api(environment_row).messages(session.id, after: after)
          last = Array(page["items"]).select { |item| item.is_a?(Hash) && item["source"] == "devin" }.last || last
          break unless page["has_next_page"] && page["end_cursor"].present?

          after = page["end_cursor"]
        end
        last ? state.with(words: last["message"]) : state
      rescue DevinApi::Error
        state
      end

      def state_of(answer)
        pull_requests = Array(answer["pull_requests"]).filter_map { |each| each["pr_url"].presence if each.is_a?(Hash) }
        status = answer["status"].to_s
        detail = answer["status_detail"].to_s
        spent = answer["acus_consumed"] && "#{answer['acus_consumed'].to_f.round(2)} ACUs"
        phase, reason = phase_of(status, detail, pull_requests)
        State.new(phase: phase, reason: reason, pull_requests: pull_requests, spent: spent)
      end

      # Devin waits for a person once it has said its piece, so a session asking with a pull request open is done.
      def phase_of(status, detail, pull_requests)
        return [ PHASE_FINISHED, nil ] if status == "exit" || detail == "finished"
        return [ PHASE_FINISHED, nil ] if WAITING.key?(detail) && pull_requests.any?
        return [ PHASE_WAITING, WAITING.fetch(detail) ] if WAITING.key?(detail)
        return [ PHASE_WORKING, nil ] if WORKING.include?(status)
        return [ PHASE_STOPPED, SUSPENDED.fetch(detail, "Devin suspended it") ] if status == "suspended"

        [ PHASE_STOPPED, status == "error" ? "its session ended with an error" : "Devin reported #{status.presence || 'nothing'}" ]
      end

      def refused_hint(error)
        case error
        when DevinApi::Unauthorized then "Check the API key, or reconnect Devin with a new one."
        when DevinApi::Forbidden then "The service user needs the UseDevinSessions permission to start sessions and ManageOrgSessions to stop one."
        when DevinApi::NotFound then "Check the organization id and the session id."
        end
      end

      # The registry's default stands in for a limit left empty.
      def acu_limit(environment_row)
        ConnectionSettings.of(environment_row).field(MAX_ACUS).to_i
      end

      def organization_of(environment_row)
        ConnectionSettings.of(environment_row).field(ORGANIZATION) || fail!("This environment has no Devin organization. Reconnect it.")
      end

      def api(environment_row) = DevinApi.new(key_of(environment_row), organization_of(environment_row))
    end
  end
end
