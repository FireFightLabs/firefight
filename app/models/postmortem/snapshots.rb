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

  def update_content!(html_content, by:)
    record_change!(IncidentEvent::POSTMORTEM_EDITED, by: by) do
      update!(content: content.merge("html" => html_content))
    end
  end

  def update_status!(new_status, by:)
    record_change!(IncidentEvent::POSTMORTEM_EDITED, by: by) do
      update!(status: new_status)
    end
  end
end
