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
    p br hr h1 h2 h3 h4 h5 h6 strong em u s del code pre blockquote
    ul ol li a span div
    table thead tbody tr th td
  ].freeze
  ALLOWED_ATTRIBUTES = %w[href title class colspan rowspan target rel].freeze

  class_methods do
    # Every way HTML reaches a postmortem, the editor, a generated draft or an older snapshot, is kept to the same tags,
    # so text a person or the model wrote never becomes markup the dashboard runs.
    def sanitized_html(html)
      Rails::Html::SafeListSanitizer.new.sanitize(html.to_s, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
    end
  end

  # A caller says which version it read and loses the race rather than the
  # writing. The row is locked so two callers holding the same version cannot both win.
  def update_content!(html_content, by:, expected_version: nil)
    sanitized = self.class.sanitized_html(html_content)

    transaction do
      lock!
      raise Postmortem::StaleContent if expected_version && content_version != expected_version.to_i

      record_change!(IncidentEvent::POSTMORTEM_EDITED, by: by) do
        update!(content: content.merge("html" => sanitized), content_version: content_version + 1)
      end
    end
  end

  # A completed postmortem is a considered account, so the learning job reads it against what the incident taught. It is
  # queued once the change is recorded, since the job credits whoever marked it completed. Completing is claimed in one
  # statement, so two people completing it at once queue the job once.
  def update_status!(new_status, by:)
    completing = transaction do
      claimed = new_status == Postmortem::STATUS_COMPLETED &&
                self.class.where(id: id).where.not(status: Postmortem::STATUS_COMPLETED).update_all(status: new_status, updated_at: Time.current) == 1
      record_change!(IncidentEvent::POSTMORTEM_EDITED, by: by) do
        update!(status: new_status)
      end
      claimed
    end
    IncidentLearningJob.perform_later(incident_id, true) if completing && defined?(FirefightAi)
  end
end
