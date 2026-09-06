module FirefightAi
  module Schemas
    class Postmortem < ::RubyLLM::Schema
      # The sections asked of the model, in reading order. The app renders
      # them under its own headings, adds the timeline itself, and fills in a
      # placeholder for any section left out. Every one is optional so the
      # model can leave out what the record does not support instead of
      # inventing it.
      SECTION_KEYS = %w[
        summary introduction deeper_dive impact resolution
        contributing_factors what_went_well action_items
      ].freeze

      OMIT = "Omit this section entirely when the incident record has nothing for it.".freeze

      description "A structured incident postmortem document"

      string :title, description: "A concise postmortem title, e.g. 'INC-031 Postmortem: API Gateway Outage'"
      string :summary, required: false, description: "Executive summary using this format: **Problem**: ... **Impact**: ... **Causes**: ... **Steps to resolve**: ... Leave out any of the four parts the record does not support. #{OMIT}"
      string :introduction, required: false, description: "Narrative introduction covering who reported, when, what happened, severity, resolution, and duration, from the record only. #{OMIT}"
      string :deeper_dive, required: false, description: "Detailed technical narrative with root cause analysis, diagnosis steps, and supporting evidence, only where the record states them. #{OMIT}"
      string :impact, required: false, description: "Detailed impact analysis covering affected users, services, and business impact, only where the record states it. #{OMIT}"
      string :resolution, required: false, description: "How the issue was fixed, with numbered steps where applicable, only where the record states it. #{OMIT}"
      string :contributing_factors, required: false, description: "Bullet list of contributing factors the record names. #{OMIT}"
      string :what_went_well, required: false, description: "Bullet list of what went well during the response, as the record shows it. #{OMIT}"
      string :action_items, required: false, description: "Bullet list of action items that follow from causes the record names. #{OMIT}"
    end
  end
end
