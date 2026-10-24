# Reads until something is done, failed or out of time, the same watch Halon keeps in a chat, from the same spec a
# runbook's watch is written in: each step a capability or a read tool with when it counts as done or failed, steps that
# wait for each other, a reads per hour ceiling and a time limit. It only reads, as whoever the run acts as. The run waits
# while it watches, and the step takes the route named for how the watch ended: succeeded, failed, timed_out or stopped.
# Failed or timed out with no step on that route fails the run.
class DefinedWorkflow::Steps::Watch < DefinedWorkflow::Steps::Base
  kind "watch"
  label "Watch"
  group GROUP_WAITING
  config_help "the same as start_watch: title, minutes, steps (each a capability or a read tool with done_when, failed_when or goal). " \
              "Outputs status and outcome, and takes the route succeeded, failed, timed_out or stopped."

  KEY_STEPS = Chat::Watch::SPEC_KEYS[:steps]
  KEY_TOOL = Chat::Watch::SPEC_KEYS[:tool]
  KEY_ARGUMENTS = Chat::Watch::SPEC_KEYS[:arguments]
  KEY_CAPABILITY = Chat::Watch::SPEC_KEYS[:capability]
  KEY_RESOURCE = Chat::Watch::SPEC_KEYS[:resource]
  KEY_CONNECTION = Integrations::Capabilities::CONNECTION_ARG
  OUTPUT_STATUS = "status".freeze
  OUTPUT_OUTCOME = "outcome".freeze
  ROUTES = Chat::Watch::ENDED
  HANDED_OFF = "watch".freeze
  CHECKPOINT_WATCH = "watch_id".freeze
  # Past its own limit the watch ends itself within a sweep or two, so the step waits this much longer before it looks.
  SETTLE = 5.minutes

  class << self
    def checks?(_config, _workspace) = true

    def output_fields(_config) = [ OUTPUT_STATUS, OUTPUT_OUTCOME ]

    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      watched = Array(config[KEY_STEPS])
      return [ "#{named} needs what it watches." ] if watched.empty?
      return [ "#{named} watches at most #{Chat::Watch::MAX_STEPS} things." ] if watched.size > Chat::Watch::MAX_STEPS

      watched.each_with_index.filter_map do |each, index|
        label = (each.is_a?(Hash) && each["label"].presence) || "item #{index + 1}"
        next "#{named} needs each thing it watches as its settings." unless each.is_a?(Hash)
        next "#{named} needs what counts as done for #{label} (done_when, failed_when or goal)." if Chat::Watch::Step.undecided?(each)
        next "#{named} reads #{label} with #{each[KEY_TOOL]}, which is not a tool in this workspace." if each[KEY_TOOL].present? && !DefinedWorkflow::Reach.tool_known?(workspace, each[KEY_TOOL])
        next "#{named} reads #{label} with #{each[KEY_TOOL]}, which can change things, and a watch only reads." if each[KEY_TOOL].present? && DefinedWorkflow::Reach.changes?(workspace, each[KEY_TOOL], each[KEY_ARGUMENTS])

        nil
      end
    end

    def reach(config, workspace, viewer: nil)
      Array(config[KEY_STEPS]).select { |each| each.is_a?(Hash) }.flat_map do |each|
        tool = each[KEY_TOOL].presence || Chat::Watch::Step.read_key(each[KEY_CAPABILITY])&.then { |key| Integrations::Capabilities.spec(key).tool_name }
        tool ? DefinedWorkflow::Reach.for_tool(workspace, tool, each[KEY_ARGUMENTS].to_h.merge(each.slice(KEY_RESOURCE, KEY_CONNECTION)), viewer: viewer) : []
      end.uniq(&:key)
    end

    def describe(config, _workspace)
      title = config[Chat::Watch::SPEC_KEYS[:title]].presence
      title || Array(config[KEY_STEPS]).filter_map { |each| each["label"] if each.is_a?(Hash) }.to_sentence.truncate(200)
    end
  end

  def perform
    @step.reload
    delivered = @step.checkpoint.to_h.dig(CHECKPOINT_DELIVERED, HANDED_OFF)
    return ended(delivered[OUTPUT_STATUS], delivered[OUTPUT_OUTCOME]) if delivered

    watch = started_watch || start_watch
    return ended(watch.status, watch.outcome) unless watch.active?

    SolidWorkflow::Park.new(wake_at: watch.expires_at + SETTLE)
  end

  private

  def ended(status, outcome)
    SolidWorkflow::Routed.new(output: { OUTPUT_STATUS => status, OUTPUT_OUTCOME => outcome }, route: status, failure: failure_words(status))
  end

  # Why the run fails when nothing follows the route, named for the step. A watch someone stopped never fails it.
  def failure_words(status)
    title = Workflow::Edit.title_of(@step.label)
    watch = started_watch
    case status
    when Chat::Watch::STATUS_TIMED_OUT
      limit = watch && Integrations::Capabilities::History.duration(watch.expires_at - watch.created_at)
      limit ? "#{title} timed out after #{limit}." : "#{title} timed out."
    when Chat::Watch::STATUS_FAILED then [ "#{title} failed.", watch&.end_reason.presence ].compact.join(" ")
    end
  end

  def started_watch
    id = @step.checkpoint.to_h[CHECKPOINT_WATCH]
    id && Chat::Watch.find_by(id: id)
  end

  def start_watch
    raise Refused, "#{@run.workflow.name} has no identity of its own to watch as." unless principal

    host = Workflow::WatchHost.new(run: @run, record: record, principal: principal)
    said = Conversation::Watches.start(host, @config.deep_stringify_keys)
    watch = host.chat.watches.order(:created_at).last
    raise Refused, said.to_s.lines.first.to_s.strip unless watch

    SolidWorkflow::Step.where(id: @step.id).update_all([ "checkpoint = COALESCE(checkpoint, '{}'::jsonb) || jsonb_build_object(?::text, ?::text)", CHECKPOINT_WATCH, watch.id ])
    watch
  end
end
