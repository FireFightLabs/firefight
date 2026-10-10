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
  # Writing a fix's code with a coding agent in the sandbox, reached through Firefight's model proxy.
  CODE_FIX = "code_fix"
  # A helper Halon hands one narrow check to, beside its own work. A few turns of reading, so a side job's model does it.
  HELPER = "helper"
  # Its own purpose, and deliberately not overridable per workspace: every vector in a workspace
  # has to come from the same model, so changing it means writing them all again.
  EMBEDDING = "embedding"
  ALL = [ POSTMORTEM, INCIDENT_RESPONSE, SUMMARY, MILESTONES, INVESTIGATION, CITATION_CHECK, LESSONS, CODE_FIX, HELPER ].freeze

  # A purpose with nothing set of its own uses its parent's model, so adding one changes nothing until it is set.
  # A postmortem with no model of its own is written on Halon's, like the rest of what Halon writes.
  PARENTS = {
    POSTMORTEM => INVESTIGATION, CITATION_CHECK => INVESTIGATION, LESSONS => CITATION_CHECK, CODE_FIX => INVESTIGATION,
    HELPER => SUMMARY
  }.freeze

  # What a workspace's own AI account runs on its quick model. Everything else, investigations and what grows from them,
  # runs on its main model.
  QUICK = [ SUMMARY, MILESTONES, INCIDENT_RESPONSE, HELPER ].freeze

  def self.quick?(purpose) = QUICK.include?(purpose)

  ANY = "any"
  OVERRIDABLE = (ALL + [ ANY ]).freeze
end
