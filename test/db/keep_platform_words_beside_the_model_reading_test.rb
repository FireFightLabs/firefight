require "test_helper"
require Rails.root.join("db/migrate/20261013120200_keep_platform_words_beside_the_model_reading")

# This migration once shared its version with another, so a database may hold its columns under the other's version.
class KeepPlatformWordsBesideTheModelReadingTest < ActiveSupport::TestCase
  COLUMNS = [ [ :chat_messages, :as_written ], [ :chat_queued_messages, :as_written ], [ :chat_queued_messages, :context ],
              [ :incident_transcript_messages, :model_content ] ].freeze

  teardown { [ Chat::Message, Chat::QueuedMessage, IncidentTranscriptMessage ].each(&:reset_column_information) }

  test "a database that already has the columns migrates past it, and one without them gets them" do
    assert_nothing_raised { migrate(:up) }

    migrate(:down)
    COLUMNS.each { |table, column| assert_not column?(table, column), "#{table}.#{column}" }

    migrate(:up)
    COLUMNS.each { |table, column| assert column?(table, column), "#{table}.#{column}" }
  end

  private

  def column?(table, column) = ActiveRecord::Base.connection.column_exists?(table, column)

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { KeepPlatformWordsBesideTheModelReading.new.migrate(direction) }
  end
end
