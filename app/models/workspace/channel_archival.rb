# Stored as an enabled flag plus a delay, offered to the settings screen as
# one choice since never is one of the answers.
module Workspace::ChannelArchival
  extend ActiveSupport::Concern

  ARCHIVE_DELAY_NEVER = "never".freeze

  Choice = Data.define(:value, :label)

  ARCHIVE_DELAY_CHOICES = [
    Choice.new(value: "0", label: "Immediately"),
    Choice.new(value: "15", label: "15 minutes"),
    Choice.new(value: "60", label: "1 hour"),
    Choice.new(value: "360", label: "6 hours"),
    Choice.new(value: "1440", label: "24 hours"),
    Choice.new(value: "4320", label: "3 days"),
    Choice.new(value: "10080", label: "7 days"),
    Choice.new(value: "43200", label: "30 days"),
    Choice.new(value: ARCHIVE_DELAY_NEVER, label: "Never")
  ].freeze

  ARCHIVE_DELAY_MINUTES = ARCHIVE_DELAY_CHOICES.map(&:value).without(ARCHIVE_DELAY_NEVER).map(&:to_i).freeze

  included do
    validate :archive_channel_delay_offered
  end

  # Turning archiving off keeps the stored delay, so turning it back on lands
  # on what the workspace had before.
  def archive_channel_delay
    archive_channel_enabled ? archive_channel_delay_minutes.to_s : ARCHIVE_DELAY_NEVER
  end

  def archive_channel_delay=(value)
    if value.to_s == ARCHIVE_DELAY_NEVER
      self.archive_channel_enabled = false
    else
      self.archive_channel_enabled = true
      self.archive_channel_delay_minutes = Integer(value.to_s, exception: false)
    end
  end

  private

  # An integer column turns junk into 0, which is immediate archiving.
  def archive_channel_delay_offered
    return unless archive_channel_enabled
    return if ARCHIVE_DELAY_MINUTES.include?(archive_channel_delay_minutes)

    errors.add(:archive_channel_delay, "is not one of the offered delays")
  end
end
