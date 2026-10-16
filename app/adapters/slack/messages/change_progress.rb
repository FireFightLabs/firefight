module Slack
  module Messages
    # A change Halon was approved to make, while it runs: a checklist of its parts redrawn in place (Checklist), with who
    # approved it and when it started under it, and Details. Only a code change says how far it got
    # (Chat::CodeFixProgress#stages). Any other change is one line saying it is under way.
    module ChangeProgress
      EMOJI = ":arrows_counterclockwise:".freeze
      WORKING = "working…".freeze
      STATUSES = {
        Chat::CodeFixProgress::STAGE_PENDING => Checklist::PENDING, Chat::CodeFixProgress::STAGE_RUNNING => Checklist::IN_PROGRESS,
        Chat::CodeFixProgress::STAGE_DONE => Checklist::COMPLETE, Chat::CodeFixProgress::STAGE_FAILED => Checklist::ERROR
      }.freeze

      # title is plain words, unescaped. footer is mrkdwn, already escaped. details is the Details button.
      def self.blocks(title:, work:, footer:, details:, rich:)
        unless work
          return Blocks::Card.new(icon: EMOJI, title: Mrkdwn.escape(title), body: "#{footer}  ·  #{WORKING}", actions: [ details ]).to_blocks(rich: rich)
        end

        items = work.stages.map do |stage|
          Checklist::Item.new(id: stage.key, title: stage.title, status: STATUSES.fetch(stage.status), detail: [ stage.detail, stage.link ].compact.join("  ").presence)
        end
        [ *Checklist.blocks(title: title, items: items, rich: rich, emoji: EMOJI),
          { type: "context", elements: [ { type: "mrkdwn", text: footer } ] }, { type: "actions", elements: [ details ] } ]
      end
    end
  end
end
