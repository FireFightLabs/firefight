# What a model is being asked to do. Each purpose picks its own model.
module AiPurpose
  POSTMORTEM = "postmortem"
  INCIDENT_RESPONSE = "incident_response"
  SUMMARY = "summary"
  ALL = [ POSTMORTEM, INCIDENT_RESPONSE, SUMMARY ].freeze

  ANY = "any"
  OVERRIDABLE = (ALL + [ ANY ]).freeze
end
