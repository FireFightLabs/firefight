# What a model is being asked to do. Each purpose picks its own model, and a
# workspace can override any of them, or all of them at once with ANY.
module AiPurpose
  POSTMORTEM = "postmortem"
  INCIDENT_RESPONSE = "incident_response"
  SUMMARY = "summary"
  ALL = [ POSTMORTEM, INCIDENT_RESPONSE, SUMMARY ].freeze

  ANY = "any"
  OVERRIDABLE = (ALL + [ ANY ]).freeze
end
