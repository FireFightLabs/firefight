module Slack
  module Messages
    # The line that goes with a page Halon's browser saw: the screen size, the page's title and address, and whether it
    # stopped before something the page would send. It is the upload's comment, or the whole message when the
    # workspace has not granted file uploads. The title is the page's own words, so it is escaped.
    module ScreenshotCaption
      def self.build(shot) = "_#{Slack::Mrkdwn.escape(shot.caption)}_"

      def self.left_out(count) = "Halon's browser took #{count} more #{'screenshot'.pluralize(count)} in this answer than are shown here."
    end
  end
end
