class IncidentTranscriptMessage
  # A conversation reads newest last, but the part worth reading is the end, so
  # a page is taken backwards from the cursor and reversed. Both the API and the
  # MCP tool hand out the same page, so the ordering, the clamp and the cursor
  # live here rather than in each of them.
  module Paging
    extend ActiveSupport::Concern

    DEFAULT_MESSAGES = 100
    MAX_MESSAGES = 500

    Page = Data.define(:messages, :more_before)

    class_methods do
      def page(before: nil, limit: nil)
        size = clamped(limit)
        scope = kept.order(posted_at: :desc, message_id: :desc).includes(:workspace_membership)
        scope = older_than(scope, find_by!(message_id: before.to_s)) if before.present?

        found = scope.limit(size + 1).to_a
        messages = found.first(size).reverse
        Page.new(messages: messages, more_before: found.size > size ? messages.first&.message_id : nil)
      end

      private

      def clamped(limit)
        (limit.presence || DEFAULT_MESSAGES).to_i.clamp(1, MAX_MESSAGES)
      end

      # Matches the sort exactly. Comparing posted_at alone would skip whatever
      # else was said in the same instant as the cursor.
      def older_than(scope, cursor)
        scope.where(
          "(incident_transcript_messages.posted_at, incident_transcript_messages.message_id) < (?, ?)",
          cursor.posted_at, cursor.message_id
        )
      end
    end
  end
end
