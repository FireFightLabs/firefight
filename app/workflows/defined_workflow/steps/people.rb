# Who a step reaches: a member by email, an incident's lead, whoever holds one of its roles, or whoever was paged or
# escalated to for it. Message a person tells them and Ask a person asks them, so both read who the same way.
module DefinedWorkflow::Steps::People
  KEY_TO = "to".freeze
  KEY_PERSON = "person".freeze
  KEY_ROLE = "role".freeze
  KEY_INCIDENT = "incident".freeze
  TO_PERSON = "person".freeze
  TO_LEAD = "lead".freeze
  TO_ROLE = "role".freeze
  TO_ON_CALL = "on_call".freeze
  TO = [ TO_PERSON, TO_LEAD, TO_ROLE, TO_ON_CALL ].freeze
  # Who needs an incident to be found.
  FROM_INCIDENT = [ TO_LEAD, TO_ROLE, TO_ON_CALL ].freeze

  module_function

  def help = "to (#{TO.join(', ')}), person (an email, for person), incident (its identifier, for lead, role and on_call), " \
             "role (an incident role's slug, for role). on_call is whoever was paged or escalated to for the incident."

  # Each problem with who the step reaches, as a sentence. verb says what it does with them, such as messages.
  def problems(config, named, verb)
    to = config[KEY_TO].to_s
    return [ "#{named} needs who it #{verb}, one of #{TO.join(', ')}." ] unless TO.include?(to)

    found = []
    found << "#{named} needs the person it #{verb}, by email." if to == TO_PERSON && config[KEY_PERSON].to_s.strip.empty?
    found << "#{named} needs the incident whose people it #{verb}." if FROM_INCIDENT.include?(to) && config[KEY_INCIDENT].to_s.strip.empty?
    found << "#{named} needs the role whose holder it #{verb}." if to == TO_ROLE && config[KEY_ROLE].to_s.strip.empty?
    found
  end

  def whom(config)
    case config[KEY_TO]
    when TO_PERSON then config[KEY_PERSON]
    when TO_LEAD then "the lead of #{config[KEY_INCIDENT]}"
    when TO_ROLE then "the #{config[KEY_ROLE]} of #{config[KEY_INCIDENT]}"
    when TO_ON_CALL then "whoever is on call for #{config[KEY_INCIDENT]}"
    end
  end

  def recipients(workspace, config, acting:)
    incident = incident(workspace, config)
    case config[KEY_TO]
    when TO_PERSON then [ workspace.workspace_memberships.resolve(config[KEY_PERSON].to_s.strip, acting: acting) ].compact
    when TO_LEAD then [ incident&.lead ].compact
    when TO_ROLE
      role = workspace.incident_roles.find_by(slug: config[KEY_ROLE].to_s)
      [ role && incident&.role_holder(role) ].compact
    when TO_ON_CALL then incident&.on_call_members.to_a
    else []
    end
  end

  def incident(workspace, config)
    return if config[KEY_INCIDENT].to_s.strip.empty?

    Mcp::Tools::GetIncident.find_by_reference(workspace.incidents.where(deleted_at: nil), config[KEY_INCIDENT].to_s)
  end

  def nobody_words(workspace, config)
    incident = incident(workspace, config)
    case config[KEY_TO]
    when TO_PERSON then "no member is #{config[KEY_PERSON]}"
    when TO_LEAD then incident ? "#{incident.identifier} has no lead" : "no incident is #{config[KEY_INCIDENT]}"
    when TO_ROLE then incident ? "nobody holds #{config[KEY_ROLE]} on #{incident.identifier}" : "no incident is #{config[KEY_INCIDENT]}"
    else incident ? "nobody was paged or escalated to for #{incident.identifier}" : "no incident is #{config[KEY_INCIDENT]}"
    end
  end
end
