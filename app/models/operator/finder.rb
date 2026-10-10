module Operator
  # Finds records from what an operator pastes, a full id, the first characters of one, or an incident number such as
  # INC-042. Each workspace numbers its own incidents, so a number can match several.
  class Finder
    KIND_INCIDENT = "incident".freeze
    KIND_RUN = "run".freeze
    KIND_CHAT = "chat".freeze
    KIND_WORKFLOW = "workflow".freeze
    KIND_BENCH = "bench".freeze
    KINDS = [ KIND_INCIDENT, KIND_RUN, KIND_CHAT, KIND_WORKFLOW, KIND_BENCH ].freeze
    BENCH_PLACE = "Chat bench".freeze

    # Fewer characters than this would match too many records.
    SHORTEST_PREFIX = 6
    LIMIT = 25
    ID_START = /\A[0-9a-f-]+\z/
    INCIDENT_NUMBER = /\A[a-z]+-\d+\z/i
    # A trace row key such as model-<id>, as it appears in a trace URL.
    SPAN_KEY = /\A([a-z]+)-([0-9a-f][0-9a-f-]{5,})\z/

    # label names the record and place is its workspace. via is the pasted id when it belongs to a record inside this
    # one. span is the trace row to open.
    Match = Data.define(:kind, :id, :label, :place, :via, :span)

    # Matches ids that start with the query, by casting the id to text. WorkflowRuns uses it for the engine's table.
    def self.id_starts(table, query)
      Arel::Nodes::NamedFunction.new("CAST", [ table[:id].as("text") ]).matches("#{ActiveRecord::Base.sanitize_sql_like(query)}%", nil, true)
    end

    def initialize(query)
      @query = query.to_s.strip.downcase
      span_key = @query.match(SPAN_KEY)
      @query = span_key[2] if span_key && !@query.match?(INCIDENT_NUMBER)
    end

    def matches
      return [] if @query.empty?

      found = @query.match?(INCIDENT_NUMBER) ? incident_numbers : by_id
      found.uniq { |match| [ match.kind, match.id, match.span ] }.first(LIMIT)
    end

    private

    def incident_numbers
      Incident.where("LOWER(identifier) = ?", @query).includes(:workspace).order(declared_at: :desc).map { |incident| incident_match(incident) }
    end

    def by_id
      return [] unless @query.match?(ID_START) && @query.delete("-").length >= SHORTEST_PREFIX

      [
        *starting(Incident.includes(:workspace)).map { |incident| incident_match(incident) },
        *starting(Investigation.includes(:workspace, :subject)).map { |run| run_match(run) },
        *starting(Conversation.includes(:workspace)).map { |conversation| chat_match(conversation) },
        *WorkflowRuns.starting_with(@query, limit: LIMIT).map { |workflow| workflow_match(workflow) },
        *starting(Conversation::BenchRun.of_scenarios).map { |run| bench_match(run) },
        *through_chats, *through_deliveries, *through_ledger, *through_model_calls, *through_messages, *through_steps
      ]
    end

    # A saved chat has its own id, and model call errors show that id.
    def through_chats
      starting(Chat.includes(owner: :workspace)).filter_map do |chat|
        owner = owner_of(chat)
        via = "Saved chat #{chat.id}"
        case owner
        when Investigation then run_match(owner, via: via)
        when Conversation then chat_match(owner, via: via)
        when Conversation::BenchResult then replay_match(owner, via: via)
        end
      end
    end

    def through_deliveries
      starting(WebhookDelivery.includes(incident_event: { incident: :workspace })).filter_map do |delivery|
        incident = delivery.incident_event&.incident
        incident_match(incident, via: "Webhook delivery #{delivery.id}") if incident
      end
    end

    # A ledger id shown in a trace leads back to the run whose tool call wrote it.
    def through_ledger
      steps = Investigation::Step.where(invocation_id: starting(Ability::Invocation).select(:id)).includes(investigation: %i[workspace subject])
      steps.map { |step| run_match(step.investigation, via: "Ledger entry #{step.invocation_id}") }
    end

    # A run's model calls are inference rows. A chat's model calls are RubyLLM usage rows.
    def through_model_calls
      runs = starting(Inference.where(inferable_type: Investigation.name).includes(inferable: %i[workspace subject])).map do |inference|
        run_match(inference.inferable, via: "Model call #{inference.id}", span: "#{Trace::KIND_MODEL}-#{inference.id}")
      end
      usages = starting(RubyLLM::ActiveRecord::Usage.where(chat_type: Chat.name)).to_a
      owners = Chat.includes(owner: :workspace).where(id: usages.map(&:chat_id)).index_by(&:id)
      chats = usages.filter_map do |usage|
        conversation = owners[usage.chat_id]&.then { |chat| owner_of(chat) }
        chat_match(conversation, via: "Model call #{usage.id}", span: "#{Trace::KIND_MODEL}-#{usage.id}") if conversation.is_a?(Conversation)
      end
      runs + chats
    end

    def through_messages
      starting(Chat::Message.includes(chat: { owner: :workspace })).filter_map do |message|
        owner = owner_of(message.chat)
        via = "Chat message #{message.id}"
        case owner
        when Investigation then run_match(owner, via: via)
        when Conversation::BenchResult then replay_match(owner, via: via)
        else chat_match(owner, via: via)
        end
      end
    end

    def through_steps
      starting(Investigation::Step.includes(investigation: %i[workspace subject])).map do |step|
        run_match(step.investigation, via: "Tool call #{step.id}", span: "#{Trace::KIND_TOOL}-#{step.id}")
      end
    end

    # A helper's chat is part of the chat or run that handed it a check, so it leads there.
    def owner_of(chat)
      owner = chat.owner
      owner.is_a?(Chat::Helper) ? owner.chat.owner : owner
    end

    def starting(scope)
      scope.where(Finder.id_starts(scope.arel_table, @query)).limit(LIMIT)
    end

    def incident_match(incident, via: nil)
      Match.new(kind: KIND_INCIDENT, id: incident.id, label: "#{incident.identifier} #{incident.name}", place: incident.workspace.name, via: via, span: nil)
    end

    def run_match(run, via: nil, span: nil)
      Match.new(kind: KIND_RUN, id: run.id, label: run.label, place: run.workspace.name, via: via, span: span)
    end

    def chat_match(conversation, via: nil, span: nil)
      Match.new(kind: KIND_CHAT, id: conversation.id, label: conversation.title.presence || Conversation::UNTITLED,
                place: conversation.workspace.name, via: via, span: span)
    end

    def bench_match(run, via: nil)
      Match.new(kind: KIND_BENCH, id: run.id, label: "Prompt #{run.prompt_version} on #{run.model}", place: BENCH_PLACE, via: via, span: nil)
    end

    # A bench replay's chat leads to its run, or for a real chat replayed, to the chat it replayed.
    def replay_match(result, via:)
      return bench_match(result.bench_run, via: via) if result.bench_run.kind == Conversation::BenchRun::KIND_SCENARIOS

      chat_match(result.replay_of, via: via) if result.replay_of
    end

    def workflow_match(workflow)
      subject = workflow.subject
      place = subject.respond_to?(:workspace) ? subject.workspace.name : workflow.subject_type.to_s
      Match.new(kind: KIND_WORKFLOW, id: workflow.id, label: workflow.workflow_class, place: place, via: nil, span: nil)
    end
  end
end
