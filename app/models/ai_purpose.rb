# Each purpose picks its own model.
module AiPurpose
  POSTMORTEM = "postmortem"
  INCIDENT_RESPONSE = "incident_response"
  SUMMARY = "summary"
  MILESTONES = "milestones"
  INVESTIGATION = "investigation"
  # Reading a finding's claims against the steps they cite. One call with no tools, so a cheaper model can do it.
  CITATION_CHECK = "citation_check"
  # Reading what an ended incident taught, once, with no tools, so a cheaper model can do it.
  LESSONS = "lessons"
  # Its own purpose, and deliberately not overridable per workspace: every vector in a workspace
  # has to come from the same model, so changing it means writing them all again.
  EMBEDDING = "embedding"
  ALL = [ POSTMORTEM, INCIDENT_RESPONSE, SUMMARY, MILESTONES, INVESTIGATION, CITATION_CHECK, LESSONS ].freeze

  # A purpose with nothing set of its own uses its parent's model, so adding one changes nothing until it is set.
  PARENTS = { CITATION_CHECK => INVESTIGATION, LESSONS => CITATION_CHECK }.freeze

  ANY = "any"
  OVERRIDABLE = (ALL + [ ANY ]).freeze
end
