module Operator
  # Lists Halon chats, and shows one chat as a trace with one timeline per turn.
  class HalonChatsController < BaseController
    PER_PAGE = 25

    def index
      page = [ params[:page].to_i, 1 ].max
      chats = ChatTrace.recent(filter).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a

      render inertia: "operator/halon/chats", props: {
        chats: HalonChatSerializer.many(chats.first(PER_PAGE)),
        page: page, more: chats.size > PER_PAGE,
        **filter_props
      }
    end

    def show
      conversation = Conversation.includes(:workspace, :subject, :investigations).find(params[:id])
      trace = ChatTrace.new(conversation)

      render inertia: "operator/halon/chat", props: {
        chat: HalonChatSerializer.one(conversation),
        turns: trace.turn_count,
        groups: TraceGroupSerializer.many(trace.groups),
        Trace::BODY_PROP => InertiaRails.optional { trace.body_for(params[Trace::SPAN_PARAM].to_s) }
      }
    end
  end
end
