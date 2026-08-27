# Outcome vocabulary + write-time validation for the alert_routing domain.
# The evaluation engine never reads this. It is the domain consumer's contract.
module PolicyRule::AlertRoutingOutcome
  ACTION_AUTO_CREATE = "auto_create_incident"
  ACTION_ATTACH = "attach_to_incident"
  ACTION_NOTIFY_ONLY = "notify_only"
  ACTION_DROP = "drop"
  ACTIONS = [ ACTION_AUTO_CREATE, ACTION_ATTACH, ACTION_NOTIFY_ONLY, ACTION_DROP ].freeze

  TARGET_MEMBER = "member"
  TARGET_TEAM = "team"
  TARGET_OWNING_TEAM = "owning_team"
  TARGET_CHANNEL = "channel"

  NOTIFY_TARGET_TYPES = [ TARGET_CHANNEL, TARGET_MEMBER, TARGET_TEAM, TARGET_OWNING_TEAM ].freeze
  INVITE_TARGET_TYPES = [ TARGET_MEMBER, TARGET_TEAM, TARGET_OWNING_TEAM ].freeze

  REQUIRED_TARGET_KEY = {
    TARGET_MEMBER => "member_id",
    TARGET_TEAM => "entry_id",
    TARGET_OWNING_TEAM => "of",
    TARGET_CHANNEL => "channel_id"
  }.freeze

  def self.errors_for(outcome, workspace: nil)
    return [ "outcome must be an object" ] unless outcome.is_a?(Hash)

    outcome = outcome.with_indifferent_access
    errors = []

    action = outcome[:action]
    errors << "unknown action #{action.inspect}" unless ACTIONS.include?(action)

    if outcome[:notify].present?
      errors << "notify is only valid for #{ACTION_NOTIFY_ONLY}" unless action == ACTION_NOTIFY_ONLY
      errors.concat(target_errors(outcome[:notify], NOTIFY_TARGET_TYPES, "notify"))
    end

    if outcome[:invite].present?
      unless [ ACTION_AUTO_CREATE, ACTION_ATTACH ].include?(action)
        errors << "invite is only valid for incident-creating actions"
      end
      unless outcome[:invite].is_a?(Array)
        return errors << "invite must be an array of targets"
      end
      outcome[:invite].each { |target| errors.concat(target_errors(target, INVITE_TARGET_TYPES, "invite")) }
    end

    errors
  end

  def self.target_errors(target, allowed_types, key)
    return [ "#{key} target must be an object" ] unless target.is_a?(Hash)

    target = target.with_indifferent_access
    type = target[:type]
    return [ "#{key} target has unknown type #{type.inspect}" ] unless allowed_types.include?(type)

    required = REQUIRED_TARGET_KEY.fetch(type)
    return [ "#{key} #{type} target requires #{required}" ] if target[required].blank?

    []
  end
end
