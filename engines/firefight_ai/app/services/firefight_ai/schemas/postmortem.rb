module FirefightAi
  module Schemas
    class Postmortem < ::RubyLLM::Schema
      # The document sections, in reading order. The app renders them under
      # its own headings.
      SECTION_KEYS = %w[
        summary introduction deeper_dive impact resolution
        contributing_factors what_went_well action_items
      ].freeze

      description "A structured incident postmortem document"

      string :title, description: "A concise postmortem title, e.g. 'INC-031 Postmortem: API Gateway Outage'"
      string :summary, description: "Executive summary using this format: **Problem**: ... **Impact**: ... **Causes**: ... **Steps to resolve**: ..."
      string :introduction, description: "Narrative introduction covering who reported, when, what happened, severity, root cause summary, resolution, and duration"
      string :deeper_dive, description: "Detailed technical narrative with root cause analysis, diagnosis steps, and supporting evidence"
      string :impact, description: "Detailed impact analysis covering affected users, services, and business impact"
      string :resolution, description: "How the issue was fixed, with numbered steps where applicable"
      string :contributing_factors, description: "Bullet list of contributing factors that led to the incident"
      string :what_went_well, description: "Bullet list of what went well during the incident response"
      string :action_items, description: "Bullet list of recommended action items to prevent recurrence"
    end
  end
end
