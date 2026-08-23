class Postmortem < ApplicationRecord
  include Postmortem::Snapshots

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
  belongs_to :generated_by, class_name: "WorkspaceMembership"
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

  def mark_generation_failed!(error)
    update!(generation_state: GENERATION_FAILED, generation_error: error.class.name.demodulize)
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
