module FirefightAi
  module Schemas
    class Postmortem < ::RubyLLM::Schema
      # Every section is nullable, not optional. Strict structured output
      # requires every key present. Null means the record had nothing for it.
      SECTION_KEYS = %w[
        summary introduction deeper_dive impact resolution
        contributing_factors what_went_well action_items
      ].freeze

      OMIT = "Return null when the incident record has nothing for it.".freeze

      description "A structured incident postmortem document"

      string :title, description: "A concise postmortem title, e.g. 'INC-031 Postmortem: API Gateway Outage'"
      optional :summary, description: "Executive summary using this format: **Problem**: ... **Impact**: ... **Causes**: ... **Steps to resolve**: ... Leave out any of the four parts the record does not support. #{OMIT}" do
        string
      end
      optional :introduction, description: "Narrative introduction covering who reported, when, what happened, severity, resolution, and duration, from the record only. #{OMIT}" do
        string
      end
      optional :deeper_dive, description: "Detailed technical narrative with root cause analysis, diagnosis steps, and supporting evidence, only where the record states them. #{OMIT}" do
        string
      end
      optional :impact, description: "Detailed impact analysis covering affected users, services, and business impact, only where the record states it. #{OMIT}" do
        string
      end
      optional :resolution, description: "How the issue was fixed, with numbered steps where applicable, only where the record states it. #{OMIT}" do
        string
      end
      optional :contributing_factors, description: "Bullet list of contributing factors the record names. #{OMIT}" do
        string
      end
      optional :what_went_well, description: "Bullet list of what went well during the response, as the record shows it. #{OMIT}" do
        string
      end
      optional :action_items, description: "Bullet list of action items that follow from causes the record names. #{OMIT}" do
        string
      end
    end
  end
end
