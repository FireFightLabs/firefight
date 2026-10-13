module Operator
  # Lists Halon chats, and shows one chat as a trace with one timeline per turn.
  class HalonChatsController < BaseController
    PER_PAGE = 25

    def index
      page = [ params[:page].to_i, 1 ].max
      chats = ChatTrace.recent(filter).includes(chat: :first_question).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a

      render inertia: "operator/halon/chats", props: {
        chats: HalonChatSerializer.many(chats.first(PER_PAGE), readable: readable),
        page: page, more: chats.size > PER_PAGE,
        **filter_props
      }
    end

    def show
      conversation = Conversation.includes(:workspace, :subject, :investigations).find(params[:id])
      trace = ChatTrace.new(conversation, readable: readable)

      render inertia: "operator/halon/chat", props: {
        chat: HalonChatSerializer.one(conversation, readable: readable),
        turns: trace.turn_count,
        groups: TraceGroupSerializer.many(trace.groups),
        Trace::BODY_PROP => InertiaRails.optional { span_body(trace) }
      }
    end
  end
end
