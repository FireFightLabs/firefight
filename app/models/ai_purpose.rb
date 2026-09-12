# Each purpose picks its own model.
module AiPurpose
  POSTMORTEM = "postmortem"
  INCIDENT_RESPONSE = "incident_response"
  SUMMARY = "summary"
  MILESTONES = "milestones"
  INVESTIGATION = "investigation"
  ALL = [ POSTMORTEM, INCIDENT_RESPONSE, SUMMARY, MILESTONES, INVESTIGATION ].freeze

  ANY = "any"
  OVERRIDABLE = (ALL + [ ANY ]).freeze
end
