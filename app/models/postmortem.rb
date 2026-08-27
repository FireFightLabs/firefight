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

  # Section keys and headings used by the AI generator to structure output
  SECTION_KEYS = %w[
    summary introduction deeper_dive impact resolution
    contributing_factors what_went_well action_items
  ].freeze

  SECTION_HEADINGS = {
    "summary" => "Summary",
    "introduction" => "Introduction",
    "deeper_dive" => "Deeper dive",
    "impact" => "Impact",
    "resolution" => "Resolution",
    "contributing_factors" => "Key contributing factors",
    "what_went_well" => "What went well",
    "action_items" => "Action items"
  }.freeze

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
  def self.start_blank!(incident, by:)
    postmortem = create!(
      incident: incident, generated_by: by, status: STATUS_DRAFT,
      title: "#{incident.identifier} Postmortem: #{incident.name}", content: { "html" => "" }
    )
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
    html = SECTION_KEYS.filter_map do |key|
      body = draft.sections[key]
      next if body.blank?

      rendered = Commonmarker.to_html(body, options: { parse: { smart: true }, render: { unsafe: true } })
      "<h2>#{SECTION_HEADINGS[key]}</h2>\n#{rendered}"
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
