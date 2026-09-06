class Postmortem < ApplicationRecord
  include Postmortem::Snapshots

  # Raised when a caller sends a body built from a version of the document that
  # somebody else has since replaced.
  class StaleContent < StandardError; end

  STATUS_DRAFT = "draft"
  STATUS_IN_PROGRESS = "in_progress"
  STATUS_IN_REVIEW = "in_review"
  STATUS_COMPLETED = "completed"
  STATUSES = [ STATUS_DRAFT, STATUS_IN_PROGRESS, STATUS_IN_REVIEW, STATUS_COMPLETED ].freeze

  # Whether an AI generation is writing this document. Separate from status,
  # which is where the document is in its editorial life. nil means nobody
  # is writing it.
  GENERATION_GENERATING = "generating"
  GENERATION_FAILED = "failed"
  GENERATION_STATES = [ GENERATION_GENERATING, GENERATION_FAILED ].freeze

  # The document's sections, in reading order. Every heading is rendered on
  # every generated document. The timeline is built from the incident record,
  # the rest is asked of the model, and a section the model had nothing for
  # is left for a person with the placeholder below.
  TIMELINE_SECTION = "timeline".freeze

  SECTION_KEYS = %w[
    summary introduction timeline deeper_dive impact resolution
    contributing_factors what_went_well action_items
  ].freeze

  AI_SECTION_KEYS = (SECTION_KEYS - [ TIMELINE_SECTION ]).freeze

  SECTION_HEADINGS = {
    "summary" => "Summary",
    "introduction" => "Introduction",
    "timeline" => "Timeline",
    "deeper_dive" => "Deeper dive",
    "impact" => "Impact",
    "resolution" => "Resolution",
    "contributing_factors" => "Key contributing factors",
    "what_went_well" => "What went well",
    "action_items" => "Action items"
  }.freeze

  EMPTY_SECTION_PLACEHOLDER = "Nothing in the incident record covers this yet. Add what you know.".freeze

  belongs_to :incident
  # Polymorphic for the same reason declared_by is: an agent can write one,
  # and saying a person did would be a lie the ledger exists to prevent.
  belongs_to :generated_by, polymorphic: true
  has_many :postmortem_updates, dependent: :destroy

  validates :generation_state, inclusion: { in: GENERATION_STATES }, allow_nil: true

  def generating?
    generation_state == GENERATION_GENERATING
  end

  def generation_failed?
    generation_state == GENERATION_FAILED
  end

  # Every entry point that kicks off a generation goes through here. Returns
  # the postmortem when this call is the one that should enqueue the job, nil
  # when a generation is already running. The unique index on incident_id
  # serializes two callers creating the placeholder at once, and the guarded
  # update serializes two callers retrying a failed one.
  # An empty document a person writes by hand, recorded like a generated one.
  # A failed generation's placeholder becomes the blank document rather than
  # standing in its way.
  def self.start_blank!(incident, by:)
    attrs = {
      status: STATUS_DRAFT, generation_state: nil, generation_error: nil,
      title: "#{incident.identifier} Postmortem: #{incident.name}", content: { "html" => "" }
    }
    postmortem = incident.postmortem
    if postmortem&.generation_failed?
      postmortem.update!(attrs)
    else
      postmortem = create!(attrs.merge(incident: incident, generated_by: by))
    end
    postmortem.record_change!(IncidentEvent::POSTMORTEM_GENERATED, by: by)
    postmortem
  end

  def self.start_generation!(incident, by:)
    existing = incident.postmortem
    if existing.nil?
      create!(
        incident: incident, generated_by: by, status: STATUS_DRAFT,
        generation_state: GENERATION_GENERATING,
        title: "Generating postmortem for #{incident.identifier}…", content: { "html" => "" }
      )
    else
      moved = where(id: existing.id, generation_state: [ nil, GENERATION_FAILED ])
        .update_all(generation_state: GENERATION_GENERATING, generation_error: nil, updated_at: Time.current) > 0
      moved ? existing.reload : nil
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def mark_generation_failed!(reason)
    reason = reason.class.name.demodulize unless reason.is_a?(String)
    update!(generation_state: GENERATION_FAILED, generation_error: reason)
  end

  def self.complete_generation!(incident, draft, generated_by:)
    html = SECTION_KEYS.map do |key|
      "<h2>#{SECTION_HEADINGS[key]}</h2>\n#{section_html(incident, draft, key)}"
    end.join("\n")

    attrs = {
      title: draft.title,
      summary: draft.summary,
      status: STATUS_DRAFT,
      generation_state: nil,
      generation_error: nil,
      model_id: draft.model,
      content: { "html" => html }
    }

    postmortem = incident.postmortem
    if postmortem
      postmortem.update!(attrs)
    else
      postmortem = create!(attrs.merge(incident: incident, generated_by: generated_by))
    end
    postmortem.record_change!(IncidentEvent::POSTMORTEM_GENERATED, by: generated_by)
    postmortem
  end

  def self.section_html(incident, draft, key)
    body = key == TIMELINE_SECTION ? Postmortem::TimelineSection.markdown(incident) : draft.sections[key]
    return "<p><em>#{EMPTY_SECTION_PLACEHOLDER}</em></p>" if body.blank?

    Commonmarker.to_html(body, options: { parse: { smart: true }, render: { unsafe: true } })
  end
  private_class_method :section_html

  validates :title, presence: true
  validates :content, presence: true
  validates :status, inclusion: { in: STATUSES }

  def html_content
    content["html"].presence || legacy_sections_to_html
  end

  private

  # Fallback for postmortems created before the HTML storage migration.
  # Converts legacy content["sections"] markdown to HTML.
  def legacy_sections_to_html
    sections = content["sections"]
    return nil if sections.blank?

    sections.map do |section|
      heading = SECTION_HEADINGS[section["key"]] || section["key"]
      body = Commonmarker.to_html(section["body"] || "", options: { parse: { smart: true }, render: { unsafe: true } })
      "<h2>#{heading}</h2>\n#{body}"
    end.join("\n")
  end
end
