# Each purpose picks its own model.
module AiPurpose
  POSTMORTEM = "postmortem"
  INCIDENT_RESPONSE = "incident_response"
  SUMMARY = "summary"
  MILESTONES = "milestones"
  INVESTIGATION = "investigation"
  # Its own purpose, and deliberately not overridable per workspace: every vector in a workspace
  # has to come from the same model, so changing it means writing them all again.
  EMBEDDING = "embedding"
  ALL = [ POSTMORTEM, INCIDENT_RESPONSE, SUMMARY, MILESTONES, INVESTIGATION ].freeze

  ANY = "any"
  OVERRIDABLE = (ALL + [ ANY ]).freeze
end
