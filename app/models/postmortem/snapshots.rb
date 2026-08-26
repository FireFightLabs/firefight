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

  # Replacing the body is the one write that can throw away somebody else's
  # work, so a caller that read the document first says which version it read
  # and loses the race rather than the writing. The row is locked for the
  # comparison, so two callers holding the same version cannot both win.
  def update_content!(html_content, by:, expected_version: nil)
    sanitized = Rails::Html::SafeListSanitizer.new.sanitize(
      html_content.to_s, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES
    )

    transaction do
      lock!
      raise Postmortem::StaleContent if expected_version && content_version != expected_version.to_i

      record_change!(IncidentEvent::POSTMORTEM_EDITED, by: by) do
        update!(content: content.merge("html" => sanitized), content_version: content_version + 1)
      end
    end
  end

  def update_status!(new_status, by:)
    record_change!(IncidentEvent::POSTMORTEM_EDITED, by: by) do
      update!(status: new_status)
    end
  end
end
