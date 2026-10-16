module Slack
  module Messages
    # A live checklist that is redrawn in place: Slack's plan block, each item a task with its status and a line under
    # it. A workspace whose Slack does not show plan blocks gets the same title and items as plain text, each marked by
    # its status, so nothing it says is lost (WorkspaceAdapter remembers which it gets).
    module Checklist
      PENDING = "pending".freeze
      IN_PROGRESS = "in_progress".freeze
      COMPLETE = "complete".freeze
      ERROR = "error".freeze

      # link is what the item produced, such as the pull request a step opened, shown after its detail.
      Link = Data.define(:text, :url)
      Item = Data.define(:id, :title, :status, :detail, :link) do
        def initialize(link: nil, **) = super
      end

      MARKS = { PENDING => ":white_circle:", IN_PROGRESS => ":hourglass_flowing_sand:", COMPLETE => ":white_check_mark:", ERROR => ":x:" }.freeze
      # A plan takes fifty tasks. A header block's title limit is used for the plan's, and a task's is kept to one line.
      MAX_ITEMS = 50
      TITLE_LIMIT = 150
      ITEM_TITLE_LIMIT = 100
      DETAIL_LIMIT = 200

      # title is plain text, a person's or the agent's words unescaped, since a plan's title is never read as markup.
      # summary repeats each item and its line under a plan, for a plan Slack shows folded, which shows its title alone.
      def self.blocks(title:, items:, rich:, emoji:, summary: false)
        shown = items.first(MAX_ITEMS)
        return plain(title, shown, emoji) unless rich
        return [ plan(title, shown) ] unless summary

        [ plan(title, shown), { type: "context", elements: [ { type: "mrkdwn", text: lines(shown).join("\n").truncate(Formatting::SECTION_TEXT_LIMIT) } ] } ]
      end

      # Slack asks for a new block id whenever a message is redrawn, so it comes from what the plan says.
      def self.plan(title, items)
        tasks = items.map { |item| task(item) }
        {
          type: "plan", block_id: "plan_#{Digest::SHA256.hexdigest([ title, tasks ].to_json)[0, 20]}",
          title: title.to_s.truncate(TITLE_LIMIT), tasks: tasks
        }
      end

      # A finished item's line is its result, and an unfinished one's says what it is doing.
      def self.task(item)
        line = (item.detail.present? || item.link) && rich_text(item.detail.to_s.truncate(DETAIL_LIMIT), item.link)
        where = [ COMPLETE, ERROR ].include?(item.status) ? :output : :details
        { task_id: item.id, title: item.title.to_s.truncate(ITEM_TITLE_LIMIT), status: item.status, where => line }.compact
      end

      def self.rich_text(text, link = nil)
        elements = [ ({ type: "text", text: text } if text.present?), ({ type: "link", url: link.url, text: link.text } if link) ].compact
        { type: "rich_text", elements: [ { type: "rich_text_section", elements: elements } ] }
      end

      # Each item on a line of its own, marked by its status, with its line and its link.
      def self.lines(items)
        items.map do |item|
          said = item.detail.present? ? Mrkdwn.escape(item.detail.to_s.truncate(DETAIL_LIMIT)) : ""
          said += "<#{item.link.url}|#{Mrkdwn.escape(item.link.text)}>" if item.link
          "#{MARKS.fetch(item.status)} #{Mrkdwn.escape(item.title.to_s.truncate(ITEM_TITLE_LIMIT))}#{"  _#{said}_" if said.present?}"
        end
      end

      def self.plain(title, items, emoji)
        [
          { type: "section", text: { type: "mrkdwn", text: "#{emoji}  *#{Mrkdwn.escape(title.to_s.truncate(TITLE_LIMIT))}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: lines(items).join("\n").truncate(Formatting::SECTION_TEXT_LIMIT) } }
        ]
      end
    end
  end
end
