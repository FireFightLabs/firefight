module Integrations
  module Pagers
    # Raises an Opsgenie alert for its responders, which pages them through their escalations and schedules, and keeps it
    # in step through Opsgenie's API (OpsgenieApi), each call authorized as the pack's tool that makes the same change.
    # Opsgenie does an alert action a moment after it accepts it, so each one waits for Opsgenie to say it was done.
    class Opsgenie < Pager
      CREATE = "create_alert".freeze
      ACKNOWLEDGE = "acknowledge_alert".freeze
      CLOSE = "close_alert".freeze
      READ = "get_alert".freeze

      TARGET_WORDS = "an Opsgenie team, escalation, schedule or user, written as team: Platform, escalation: Checkout, " \
                     "schedule: Platform rota or user: ana@acme.io".freeze
      PAGES_WORDS = "a team, escalation, schedule or person, whose rotation pages whoever is on call".freeze
      SYNC_TOOLS = [ CREATE, ACKNOWLEDGE, CLOSE, READ ].freeze
      ON_CALL_TOOL = "who_is_on_call".freeze
      ALERT_SOURCE = AlertSource::PROVIDER_OPSGENIE
      ID = "id".freeze
      ALIAS = "alias".freeze
      DEFAULT_RESPONDER = "team".freeze

      def page(title:, details:, target:, key:)
        responder = responder_for(target)
        arguments = { "message" => title, "responders" => [ responder ], "alias" => key }
        alert_id = through(CREATE, arguments, "raise an Opsgenie alert") do
          accepted = api.create_alert(message: title, description: details, alias_name: key, responders: [ responder ])
          settled!(accepted, "raise the alert")&.dig("alertId")
        end
        Paging::Raised.new(external_id: alert_id.presence, reference: nil, url: nil)
      rescue OpsgenieApi::Error => error
        raise Paging::Failed, Sentence.join("Opsgenie did not raise the alert", error.message)
      end

      def acknowledge(external_id, key: nil) = act(ACKNOWLEDGE, :acknowledge, "acknowledge", external_id, key)

      def resolve(external_id, key: nil) = act(CLOSE, :close, "close", external_id, key)

      def knows?(external_id)
        through(READ, { "alert" => external_id }, "read the alert") { api.alert(external_id, ID) }.present?
      rescue OpsgenieApi::Error => error
        raise Paging::Failed, Sentence.join("Opsgenie did not answer for alert #{external_id}", error.message) unless error.is_a?(NotFound)

        false
      end

      def on_call
        through(ON_CALL_TOOL, {}, "read who is on call") do
          api.schedules.reject { |schedule| schedule["enabled"] == false }.flat_map do |schedule|
            people = Array(api.on_calls(schedule["id"], by_name: false)["onCallRecipients"])
            people.map { |email| Paging::OnCall.new(name: email, email: email, covers: "#{schedule['name']} schedule") }
          end
        end
      rescue OpsgenieApi::Error => error
        raise Paging::Failed, Sentence.join("Opsgenie did not say who is on call", error.message)
      end

      private

      def api
        @api ||= begin
          key = settings.credential(Packs::Opsgenie::API_KEY)
          raise Paging::Failed, "#{@integration.name} has no Opsgenie key. Reconnect it on the Integrations page." if key.nil?

          OpsgenieApi.new(key, region: settings.region&.key)
        end
      end

      # An alert raised a moment ago may not have its id here yet, and its alias finds it while it is open.
      def act(tool, call, verb, external_id, key)
        identifier, type = external_id.present? ? [ external_id, ID ] : [ key, ALIAS ]
        raise Paging::Failed, "Firefight does not know which Opsgenie alert this is yet." if identifier.blank?

        through(tool, { "alert" => identifier, "identifier_type" => type }, "#{verb} the Opsgenie alert") do
          settled!(api.public_send(call, identifier, type, note: nil), "#{verb} alert #{identifier}")
        end
        nil
      rescue OpsgenieApi::Error => error
        raise Paging::Failed, Sentence.join("Opsgenie did not #{verb} alert #{identifier}", error.message)
      end

      # What Opsgenie said once it did the request, or nil while it has not said. A request it could not do is Failed.
      def settled!(accepted, what)
        status = accepted["requestId"].present? ? api.settle(accepted["requestId"]) : nil
        return status if status.nil? || status["isSuccess"]

        raise Paging::Failed, Sentence.join("Opsgenie could not #{what}", status["status"])
      end

      # "team: Platform" names a team, and a bare name is a team too, since teams are what Opsgenie routes alerts to.
      def responder_for(target)
        kind, name = target.to_s.split(":", 2).map(&:strip)
        kind, name = DEFAULT_RESPONDER, kind if name.nil?
        kind = kind.to_s.downcase
        raise Paging::Failed, "Name who to page in Opsgenie, as #{TARGET_WORDS}." if name.blank?
        raise Paging::Failed, "Opsgenie pages a #{OpsgenieApi::RESPONDER_TYPES.to_sentence(last_word_connector: ' or ')}, not a #{kind}." unless OpsgenieApi::RESPONDER_TYPES.include?(kind)

        kind == "user" ? { "type" => kind, "username" => name } : { "type" => kind, "name" => name }
      end
    end
  end
end
