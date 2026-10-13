# What one of a coding agent's model calls was for, told from the tools its answer called, so the ledger shows how many
# calls a code fix spends finding code, reading it, changing it and testing it. Tool names are OpenCode's, the same ones
# Integrations::SandboxAgentEvents reads, and Firefight's own tools come with the agent's server name in front.
class CodeAgent::CallKind
  SEARCH = "search"
  READ = "read"
  EDIT = "edit"
  TEST = "test"
  # Reading connected systems or the providers' documentation through Firefight's tools.
  LOOKUP = "lookup"
  QUESTION = "question"
  PLAN = "plan"
  GIT = "git"
  WEB = "web"
  SHELL = "shell"
  # No tool at all, so the call wrote the agent's last words.
  ANSWER = "answer"
  OTHER = "other"
  ALL = [ SEARCH, READ, EDIT, TEST, LOOKUP, QUESTION, PLAN, GIT, WEB, SHELL, ANSWER, OTHER ].freeze

  TOOLS = {
    "read" => READ, "grep" => SEARCH, "glob" => SEARCH, "list" => SEARCH, "codesearch" => SEARCH, "lsp" => SEARCH,
    "edit" => EDIT, "write" => EDIT, "apply_patch" => EDIT, "multiedit" => EDIT, "patch" => EDIT,
    "todowrite" => PLAN, "todoread" => PLAN, "task" => PLAN, "webfetch" => WEB, "websearch" => WEB
  }.freeze

  # Firefight's own tools, by the name the agent's server gives them.
  OWN_TOOLS = {
    CodeAgent::ReadTools::LIST => LOOKUP, CodeAgent::ReadTools::DESCRIBE => LOOKUP, CodeAgent::ReadTools::CALL => LOOKUP,
    CodeAgent::ReadTools::SKILLS => LOOKUP, CodeAgent::ReadTools::SKILL => LOOKUP, Chat::Tools::Docs::SEARCH => LOOKUP,
    Chat::Tools::Docs::READ => LOOKUP, CodeAgent::QuestionTools::ASK => QUESTION, CodeAgent::QuestionTools::WAIT => QUESTION,
    Chat::Tools::Web::SEARCH => WEB, Chat::Tools::Web::READ => WEB, CodeAgent::SandboxTools::START => SHELL
  }.freeze

  SEARCH_COMMANDS = %w[rg grep egrep fgrep find fd ls tree ag ack].freeze
  READ_COMMANDS = %w[cat sed head tail less nl wc awk jq].freeze
  GIT_SEARCHES = %w[grep log ls-files blame].freeze
  GIT_READS = %w[show diff].freeze
  # A command's own settings in front of it, such as RAILS_ENV=test.
  ASSIGNMENT = /\A[A-Za-z_][A-Za-z0-9_]*=/

  # The kinds of the calls an answer made, in the order first seen. calls are FirefightAi::ModelProxy::Calls::Call.
  def self.of(calls)
    return [ ANSWER ] if calls.empty?

    calls.map { |call| kind(call.name, call.input) }.uniq
  end

  def self.kind(name, input)
    return TOOLS[name] if TOOLS.key?(name)
    return command(input.to_h["command"]) if name == "bash"

    OWN_TOOLS.find { |tool, _kind| name.end_with?("_#{tool}") || name == tool }&.last || OTHER
  end

  # A command that runs tests is a test whatever else it chains, and otherwise the first step that is not a cd says.
  def self.command(text)
    return TEST if Integrations::SandboxAgentEvents.runs_tests?(text)

    words = text.to_s.split(/&&|\|\||;|\|/).map { |part| part.strip.split.drop_while { |word| word.match?(ASSIGNMENT) } }.reject { |part| part.empty? || part.first == "cd" }.first
    return SHELL if words.nil?

    program = File.basename(words.first.to_s)
    return SEARCH if SEARCH_COMMANDS.include?(program)
    return READ if READ_COMMANDS.include?(program)
    return SHELL unless program == "git"
    return SEARCH if GIT_SEARCHES.include?(words.second)
    return READ if GIT_READS.include?(words.second)

    GIT
  end
end
