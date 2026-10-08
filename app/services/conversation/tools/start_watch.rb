# Keeps watching something after the answer and reports back by itself, for a person who asks to be told when a run, a
# build or a deploy finishes. It only reads, as the person who asked.
class Conversation::Tools::StartWatch < RubyLLM::Tool
  STEP = {
    "type" => "object",
    "properties" => {
      "label" => { "type" => "string", "description" => "What this step is, as the person would say it, such as Release run #46 or Hosting build" },
      "capability" => { "type" => "string", "enum" => Integrations::Capabilities::SPECS.values.reject(&:writes).map(&:tool_name),
                        "description" => "The read that checks it. run_history follows a run, build or deploy by its status, and says at once " \
                                         "when a job or step inside it fails. Any other read needs done_when, failed_when or goal. Give this or tool" },
      "tool" => { "type" => "string",
                  "description" => "Instead of a capability, any read tool you hold, by the name you call it, with its arguments, such as a " \
                                   "provider's API request with method GET for one workflow run. A tool that can also change things only " \
                                   "reads here. Needs done_when, failed_when or goal. Find the right read in the provider's skill, " \
                                   "search_docs or the web (optional)" },
      "resource" => { "type" => "string", "description" => "The resource on the map, by name or map id, as for the capability itself (a capability only)" },
      "connection" => { "type" => "string", "description" => "The connection to ask, when the capability needs one named (optional)" },
      "name" => { "type" => "string", "description" => "run_history only: follow runs whose workflow, pipeline or kind contains this, such as release, build or deploy (optional)" },
      "run" => { "type" => "string", "description" => "run_history only: the run to follow by its id or number, such as 46. Without it, the first run of that name that starts around now (optional)" },
      "report_start" => { "type" => "boolean", "description" => "run_history only: also say when the run starts, when the person asked to hear that (optional)" },
      "done_when" => { "type" => "string", "description" => "Text in the read's answer that means it is done, such as running (optional)" },
      "failed_when" => { "type" => "string", "description" => "Text in the read's answer that means it failed, such as crashed (optional)" },
      "goal" => { "type" => "string", "description" => "What done looks like in a sentence, judged only when the answer changed and no text above decides (optional)" },
      "arguments" => { "type" => "object", "description" => "Other arguments the capability takes, such as stream for search_logs, or all of the tool's arguments (optional)" }
    },
    "required" => %w[label]
  }.freeze

  description "Watch something after you answer and report back on your own, when the person asks to be told when it finishes " \
              "or reaches a step: a CI run, a build, a deploy, a resource coming back. It only reads, as the person, through " \
              "the capabilities, about every minute and at once when a connection reports a change. Each milestone the person " \
              "asked about and the end are posted in this chat, its thread and their direct messages, with the " \
              "reason and what the logs show when something fails, and where it leaves the purpose. Give it the steps in order. " \
              "A run that never shows up in its history is handed back to you within minutes to find another read. The time limit is learned from " \
              "run history (twice the usual, at most 24 hours). Pass minutes only when the person asked for a limit, and " \
              "expected_minutes only from memory when run history has none. Say what it answers about the limit."

  def self.tool_name = "start_watch"

  def initialize(turn)
    super()
    @turn = turn
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "title" => { "type" => "string", "description" => "What is watched, as the person would say it, such as release run #46 and the deploy" },
        "purpose" => { "type" => "string",
                       "description" => "Why the person wants this, the goal in their own words, such as get GitHub releases deploying through " \
                                        "the webhook again. Every report says where things stand against it" },
        "steps" => { "type" => "array", "items" => STEP, "description" => "What to follow, in order, at most #{Chat::Watch::MAX_STEPS}" },
        "minutes" => { "type" => "integer", "description" => "Only when the person asked: how long to watch, at most #{Chat::Watch::LONGEST.in_minutes.to_i} (optional)" },
        "expected_minutes" => { "type" => "integer", "description" => "Only from memory, when run history cannot show it: how long this usually takes (optional)" }
      },
      "required" => %w[title steps]
    }
  end

  def call(tool_call: nil, **arguments)
    Conversation::Watches.start(@turn, arguments.deep_transform_keys(&:to_s))
  end
end
