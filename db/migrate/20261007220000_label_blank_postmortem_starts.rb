class LabelBlankPostmortemStarts < ActiveRecord::Migration[8.1]
  # A blank start used to be recorded as an AI generation. Its snapshot is the only one with an empty document, since a
  # generation always writes every section heading, so the empty html is what tells them apart. Safe to run again.
  def up
    execute <<~SQL
      UPDATE incident_events
      SET event_type = 'postmortem.started'
      FROM postmortem_updates
      WHERE incident_events.eventable_type = 'PostmortemUpdate'
        AND incident_events.eventable_id = postmortem_updates.id
        AND incident_events.event_type = 'postmortem.generated'
        AND postmortem_updates.update_type IN ('generated', 'started')
        AND postmortem_updates.content->>'html' = ''
    SQL

    execute <<~SQL
      UPDATE postmortem_updates
      SET update_type = 'started'
      WHERE update_type = 'generated'
        AND content->>'html' = ''
    SQL
  end

  # The code before this names a blank start's revision but not its event, so only the event goes back.
  def down
    execute <<~SQL
      UPDATE incident_events SET event_type = 'postmortem.generated' WHERE event_type = 'postmortem.started'
    SQL
  end
end
