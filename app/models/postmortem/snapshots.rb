module Postmortem::Snapshots
  extend ActiveSupport::Concern

  included do
    include Trackable
    tracked_by PostmortemUpdate
  end

  def snapshot_attributes
    {
      postmortem: self,
      incident: incident,
      title: title,
      summary: summary,
      content: content,
      status: status,
      model_id: model_id
    }
  end

  ALLOWED_TAGS = %w[
    p br hr h1 h2 h3 h4 h5 h6 strong em u s code pre blockquote
    ul ol li a span div
    table thead tbody tr th td
  ].freeze
  ALLOWED_ATTRIBUTES = %w[href title class colspan rowspan target rel].freeze

  def update_content!(html_content, by:)
    sanitized = Rails::Html::SafeListSanitizer.new.sanitize(
      html_content.to_s, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES
    )

    record_change!(IncidentEvent::POSTMORTEM_EDITED, by: by) do
      update!(content: content.merge("html" => sanitized))
    end
  end

  def update_status!(new_status, by:)
    record_change!(IncidentEvent::POSTMORTEM_EDITED, by: by) do
      update!(status: new_status)
    end
  end
end
