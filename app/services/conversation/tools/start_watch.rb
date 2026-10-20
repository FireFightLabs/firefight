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
                  "description" => "Instead of a capability, any read you can make in this chat, by the tool's name, with its arguments: a " \
                                   "provider's general read, such as its API request with method GET for one workflow run by its id " \
                                   "(workflows/release/runs/<id>) or for a workflow's newest run, any tool that reads, or one of Firefight's " \
                                   "own reads. For a code host's CI, prefer run_history with run, which brings its jobs. A tool that can also " \
                                   "change things only reads here. Needs done_when, failed_when or goal. Find the right read in the " \
                                   "provider's skill, search_docs or the web (optional)" },
      "focus" => { "type" => "string",
                   "description" => "tool only: the part of a JSON answer to watch, as a dotted path such as data.status or data.nodes, when " \
                                    "the answer is long and only that part says how it stands (optional)" },
      "resource" => { "type" => "string", "description" => "The resource on the map, by name or map id, as for the capability itself (a capability only)" },
      "connection" => { "type" => "string", "description" => "The connection to ask, when the capability needs one named (optional)" },
      "name" => { "type" => "string", "description" => "run_history only: follow runs whose workflow, pipeline or kind contains this, such as release, build or deploy (optional)" },
      "run" => { "type" => "string", "description" => "run_history only: the run to follow by its id, its number, such as 46, or its own name where the provider " \
                                       "names each run, such as release-v1-4-0. Always give it when you started the run or can identify it, so the watch " \
                                       "follows that exact run. Without it, the first run of that name that starts around now, or after the steps it waits for began (optional)" },
      "report_start" => { "type" => "boolean", "description" => "run_history only: also say when the run starts, when the person asked to hear that (optional)" },
      "done_when" => { "type" => "string", "description" => "What in the read's answer means it is done, such as status success (optional)" },
      "failed_when" => { "type" => "string", "description" => "What in the read's answer means it failed, such as status failure or crashed (optional)" },
      "goal" => { "type" => "string", "description" => "Keep checking until this holds: the question in plain words, such as every instance of web runs " \
                                                       "the new version, or the error rate stays under 1% for ten minutes. A tool whose answer is a run history, " \
                                                       "such as a provider's job runs, is judged by the run's own status, the run its run argument " \
                                                       "names or the one that starts around now. Any other read is judged by a model over its recent " \
                                                       "readings, with done_when and failed_when as what to look for, on each reading that changed and " \
                                                       "every few minutes on one that did not (optional)" },
      "arguments" => { "type" => "object", "description" => "Other arguments the capability takes, such as stream for search_logs, or all of the tool's arguments (optional)" },
      Chat::Watch::SPEC_KEYS[:waits_for] => {
        "type" => "array", "items" => { "type" => "string" },
        "description" => "The earlier steps this one waits for, by their labels or their numbers counting from 1, such as a health check " \
                         "that waits for the deploy it checks. It is not read until every one of them succeeded, and then counts only " \
                         "what came after them: runs and deploys started once they began, containers created since, and log lines " \
                         "since they finished. When one of them fails or cannot be followed, this step is skipped. A step that waits " \
                         "for nothing is read at once, so steps that do not depend on each other go side by side. With add_to, it may " \
                         "name the watch's own steps (optional)"
      },
      Chat::Watch::SPEC_KEYS[:new_deploy] => {
        "type" => "object",
        "description" => "When the step waits for a deploy, a rollout or a release to go live: what counts as the new one. The watch keeps the deploy " \
                         "live when it starts and counts only a newer one that finished rolling out and is serving, so the deploy already live " \
                         "never reads as the new one. Name the version whenever you know it, such as the commit the release run built, and give " \
                         "{} for any newer deploy. A recent_deploys step, and a resource_status or tool step whose goal speaks of a deploy, " \
                         "rollout or release, waits for a new deploy on its own (optional)",
        "properties" => {
          "resource" => { "type" => "string", "description" => "The resource deployed, by name or map id, when the step reads with a tool (optional, the step's resource)" },
          "connection" => { "type" => "string", "description" => "The connection that deploys it, when more than one could (optional)" },
          "commit" => { "type" => "string", "description" => "The commit that has to be live, at least its first 7 characters (optional)" },
          "tag" => { "type" => "string", "description" => "The tag that has to be live, such as v1.4.0. It is read as its commit through the connected code host (optional)" },
          "branch" => { "type" => "string", "description" => "Only a newer deploy from this branch counts (optional)" },
          "environment" => { "type" => "string", "description" => "Only deploys to this environment count, such as staging, where the provider deploys one " \
                                                                  "resource to several (optional, production)" },
          "repository" => { "type" => "string", "description" => "The repository a tag is in, by name on the map, when the resource is not linked to one (optional)" }
        }
      }
    },
    "required" => %w[label]
  }.freeze

  description "Write a watch: keep checking something after you answer, with any read you hold, until a condition in plain words " \
              "holds, and report back on your own. Use it when the person asks to be told when something finishes or reaches a step: " \
              "a CI run, a build, a deploy, a resource coming back. It only reads, as the person, about every minute and at once when " \
              "a connection reports a change, within a ceiling on reads an hour. Each milestone the person asked about, each job or " \
              "step as it starts or passes, and the end are posted in this chat, its thread and their direct messages, with the " \
              "reason and what the logs show when something fails, and where it leaves the purpose. Give it the steps in order, " \
              "and say which steps each one waits for with waits_for, from the order the person described or the runbook " \
              "gives: something that only makes sense once another thing is done, such as a deploy after the run that starts " \
              "it or a health check after its own deploy, waits for it, and things that happen side by side wait for nothing. " \
              "A reading that shows a step failed is read once more before the watch ends on it. " \
              "A read that finds nothing to follow, such as a run that never shows up, is handed back to you to repair with " \
              "repair_watch. The time limit is learned from run history (twice the usual, at most 24 hours). Pass minutes only " \
              "when the person asked for a limit, and expected_minutes only from memory when run history has none. Say what it " \
              "answers about the limit. Anything you start that keeps running, such as a workflow, a build, a deploy or a " \
              "test run, is yours to follow: start a watch on it in the same turn, with its purpose. When the person starts " \
              "something that takes a while, offer to watch it for them. One watch per subject: steps on the same release, " \
              "deploy, run or incident as a watch going in this chat, such as the rollout and health checks after a release " \
              "build, join it with add_to, and something unrelated, such as a database backup during a release, is separate. " \
              "In the dashboard chat the person sees the watches going in the Watching strip above the message box, so point " \
              "there rather than listing them. A step waiting for a deploy, a rollout or a release to go live counts only a " \
              "deploy newer than the one live when the watch starts, so pass new_deploy with the version you expect whenever " \
              "you know it, such as the commit the release run built or the tag it pushed."

  def self.tool_name = "start_watch"

  def initialize(turn)
    super()
    @turn = turn
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "title" => { "type" => "string", "description" => "What the watch waits on, a few words naming the end it waits for, such as Deploy finished or " \
                                                          "Release run #46 passed, shown as Watch \"Deploy finished\". Always give it for a new watch. With add_to, only " \
                                                          "to rename the watch for everything it now waits on" },
        "purpose" => { "type" => "string",
                       "description" => "Why the person wants this, the goal in their own words, such as get releases deploying through " \
                                        "the webhook again. Every report says where things stand against it. With add_to, only to " \
                                        "restate the goal for everything the watch now covers" },
        "steps" => { "type" => "array", "items" => STEP, "description" => "What to follow, in order, at most #{Chat::Watch::MAX_STEPS}" },
        "minutes" => { "type" => "integer", "description" => "Only when the person asked: how long to watch, at most #{Chat::Watch::LONGEST.in_minutes.to_i}. " \
                                                              "With add_to, how long from now the added steps need (optional)" },
        "expected_minutes" => { "type" => "integer", "description" => "Only from memory, when run history cannot show it: how long this usually takes (optional)" },
        "reads_per_hour" => { "type" => "integer",
                              "description" => "Only when a provider's documented rate limit or cost is tighter than the default of " \
                                               "#{Chat::Watch::READS_PER_STEP} reads an hour for each step: the most reads an hour this watch may " \
                                               "make, between #{Chat::Watch::FEWEST_READS} and #{Chat::Watch::MOST_READS} (optional)" },
        Conversation::Watches::ADD_TO_ARG => {
          "type" => "string",
          "description" => "The id of a watch going in this chat that follows the same subject as these steps, the same release, " \
                           "deploy, run or incident, to add them to it rather than start another. They follow its own steps, and its " \
                           "time limit moves to leave them time (optional)"
        },
        Conversation::Watches::SEPARATE_ARG => {
          "type" => "boolean",
          "description" => "true when a watch is going in this chat and these steps follow something unrelated to it, such as a " \
                           "database backup during a release. While one is going, give add_to or this (optional)"
        }
      },
      "required" => %w[steps]
    }
  end

  def call(tool_call: nil, **arguments)
    Conversation::Watches.start(@turn, arguments.deep_transform_keys(&:to_s), choose: true)
  end
end
