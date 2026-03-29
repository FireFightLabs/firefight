class Postmortem < ApplicationRecord
  include Postmortem::Snapshots

  STATUS_DRAFT = "draft"
  STATUS_IN_PROGRESS = "in_progress"
  STATUS_IN_REVIEW = "in_review"
  STATUS_COMPLETED = "completed"
  STATUSES = [ STATUS_DRAFT, STATUS_IN_PROGRESS, STATUS_IN_REVIEW, STATUS_COMPLETED ].freeze

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

  validates :title, presence: true
  validates :content, presence: true
  validates :status, inclusion: { in: STATUSES }

  def sections
    content["sections"] || []
  end

  def section(key)
    sections.find { |s| s["key"] == key.to_s }
  end

  def html_content
    content["html"].presence || sections_to_html
  end

  private

  def sections_to_html
    return nil if sections.blank?

    sections.map do |section|
      heading = SECTION_HEADINGS[section["key"]] || section["key"]
      body = Commonmarker.to_html(section["body"] || "", options: { parse: { smart: true }, render: { unsafe: true } })
      "<h2>#{heading}</h2>\n#{body}"
    end.join("\n")
  end
end
