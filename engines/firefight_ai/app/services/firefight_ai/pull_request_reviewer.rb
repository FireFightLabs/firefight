module FirefightAi
  # Reviews a pull request the way a senior engineer who has been on call for these services would: ordinary review,
  # the failure patterns that apply to any stack, and what only Firefight knows (past incidents, the resource map and
  # live data). It loops with the tools the app hands it, the code sandbox holding the pull request's head among them,
  # and reports each problem with the tool the app hands for that, once its failure chain is shown. A large pull request
  # is reviewed in parts on the same chat, so every file is read and what one part learned carries into the next. The
  # app checks each report before it is written, keeps the record and decides who it reads as.
  class PullRequestReviewer
    FEATURE = "pull_request_review".freeze
    # One part of the diff, in characters. A part leaves room for reading the code around it in the same window.
    PART_LIMIT = 40_000
    # Enough to read around every change of a part several ways and prove what it finds, never a runaway.
    TURNS_PER_PART = 40

    # One file's diff, or a piece of one too large for a part, with where the piece sits in the file.
    Piece = Data.define(:path, :text, :index, :count) do
      def whole? = count == 1

      def label = whole? ? path : "#{path} (piece #{index} of #{count})"
    end

    Part = Data.define(:pieces) do
      def paths = pieces.map(&:path).uniq

      def text = pieces.map(&:text).join
    end

    # files are [path, diff] pairs in the order to read them, each a git style diff of one file. A file that fits joins
    # the part being filled, and one larger than a part is split at its hunks, a hunk larger than a part at its lines, so
    # every line of every file is in exactly one part.
    def self.parts(files, limit: PART_LIMIT)
      pieces = files.flat_map { |path, text| pieces_of(path, text.to_s, limit) }
      pieces.each_with_object([]) do |piece, parts|
        last = parts.last
        if last && last.sum { |each| each.text.size } + piece.text.size <= limit
          last << piece
        else
          parts << [ piece ]
        end
      end.map { |pieces_of_part| Part.new(pieces: pieces_of_part) }
    end

    def self.pieces_of(path, text, limit)
      return [ Piece.new(path: path, text: text, index: 1, count: 1) ] if text.size <= limit

      header, *hunks = text.split(/^(?=@@ )/)
      chunks = hunks.flat_map { |hunk| hunk.size + header.size <= limit ? [ hunk ] : lines_within(hunk, limit - header.size) }
      grouped = chunks.each_with_object([]) do |chunk, groups|
        if groups.last && groups.last.sum(&:size) + chunk.size + header.size <= limit
          groups.last << chunk
        else
          groups << [ chunk ]
        end
      end
      grouped.each_with_index.map { |group, index| Piece.new(path: path, text: header + group.join, index: index + 1, count: grouped.size) }
    end

    # A hunk too large for a part, cut at its lines, each cut saying where it continues so a reader never takes it for a
    # whole hunk.
    def self.lines_within(hunk, room)
      lines = hunk.lines
      heading = lines.first
      body = lines.drop(1)
      cuts = body.each_with_object([ [] ]) do |line, cut|
        cut << [] if (cut.last.sum(&:size) + line.size + heading.size) > room && cut.last.any?
        cut.last << line
      end
      cuts.each_with_index.map { |cut, index| (index.zero? ? heading : "@@ continued from the hunk above @@\n") + cut.join }
    end

    private_class_method :pieces_of, :lines_within

    # choice is the ModelChoice the app picked for reviewing code. purpose is what the ledger and the output cap read it as.
    def initialize(workspace, inferable:, choice:, purpose: AiPurpose::CODE_REVIEW)
      @workspace = workspace
      @inferable = inferable
      @choice = choice
      @purpose = purpose
    end

    # The app has saved nothing on the chat yet. overview is what the whole review starts from, as sections the app
    # wrote: the pull request, every file and the part it is in, what the map and past incidents say about where it
    # runs. Everything a person wrote there, the title and description among it, is evidence.
    def open(chat, tools:, overview:, deferred_tools: [])
      FirefightAi.translating_errors do
        FirefightAi.ready_chat(chat, choice: @choice, instructions: self.class.system_prompt, tools: tools, deferred_tools: deferred_tools)
        next if chat.to_llm.messages.any? { |message| message.role == :user }

        chat.add_message(role: :user, content: opening(overview), cache_until_here: true)
      end
    end

    # One part, until the agent calls the tool that ends it (answered) or the budget, turns or time run out. budget
    # carries what the review spent and turned before this part, purse what it spends with the checks beside it.
    def review_part(chat:, part:, number:, total:, budget:, purse:, answered:, canceled: AgentLoop::NEVER_CANCELED, on_step: nil, &on_turn)
      FirefightAi.translating_errors do
        FirefightAi.bind(chat, @choice)
        chat.add_message(role: :user, content: part_material(part, number, total))
        AgentLoop.new(
          chat: chat, budget: budget, answered: answered, canceled: canceled, on_step: on_step, memory: chat, inference: inference_context,
          output: FirefightAi.output_cap(@purpose, choice: @choice), choice: @choice, purpose: @purpose, purse: purse, retry_malformed: true, steady: true
        ).run(&on_turn)
      end
    end

    def self.prompt_version = Prompt.version(system_prompt)

    def self.system_prompt
      <<~PROMPT
        You are Halon, the SRE on this team, reviewing a pull request before it merges. You review it as a careful senior engineer who has also been on call for the services it touches: you find what would break once it merges, and you show how it breaks.

        What you look for:
        - Ordinary review first: bugs, two workers or two requests racing over the same row, permission and ownership checks that are missing or can be bypassed (a feature flag that is off is no protection), retries and waits that last too long or never end, errors swallowed quietly, a list read only to its first page, data that changes shape, goes stale or is lost, and security holes.
        - Failure patterns that hold for any stack and any database. Check every change against them, and raise one only when the real context makes it a risk:
          - A migration that locks or rewrites a table that is large in production. Read the table's real size before calling it large, from a connected database (its row count or size) or the resource map. The same migration on a small table is fine.
          - Schema and code out of step, either way: a column, table or index dropped or renamed while code still reads it, or code that needs one the migration has not added yet.
          - Something removed or renamed that is still in use: an API field, an event or message type, an environment variable or setting, a route. Search for who still uses it, in this repository and in the services the map links to it, before you raise it.
          - A change that only works when deployed in a set order, such as the code before the migration, a producer before its consumer, or one service before another.
        - Lessons the team approved are listed with the facts, from past incidents and from what people changed on pull requests Halon opened. Check the change against each one that applies. A change that goes against one is a finding when its failure chain holds here, and it names the lesson.
        - These are a floor. On top, use what only Firefight has: past incidents and postmortems that touched the changed code or its services, what depends on it on the resource map, live production data where a connection reads it, and your own reasoning about how the change behaves once it runs. A past incident is evidence when the change repeats what caused it.

        How you work:
        - The pull request's head is checked out in your sandbox. Read around each change with the code tools: the whole file, who calls it, where things are defined, the language server for an exact answer, and a shell command for anything else, such as a search across the repository. Read the base branch the same way, with its commit as the ref, to see what was there before rather than guess.
        - The repository's own CI results for the head are reads too, such as its checks and their logs, when the code host's tools show them.
        - Prove each problem before you report it. Write its failure chain: from the change, step by step, to what fails in production and who notices. Each step rests on something you read, such as a line of code, an incident, a postmortem, a resource on the map or a metric. A step you could not show is a guess, so read until it is shown or let the problem go.
        - Report each problem with report_finding as soon as it is shown, one at a time. A separate check verifies it before it is written, and tells you whether it was written, which earlier findings it changed, or why it was dropped. A dropped finding stays dropped unless you find new evidence.
        - Report only what is wrong with this change or what it breaks. Style preferences, naming, missing comments and the order of tests are not findings. A line the pull request did not change can hold a finding when this change makes it wrong.
        - One problem is one finding. When it spans files, report it once where it is fixed and name the other files in why.
        - Once every file of the part in front of you is reviewed, call finish_part.

        #{Manual::THINKING}

        How you label a finding:
        - severity: critical when merging it breaks production for its users, loses or corrupts data, or opens a hole someone can use. major for a real bug or risk normal use will hit. minor for one that needs unusual conditions. trivial for something small that costs little.
        - serious: true when merging it as it is would likely cause an incident.
        - effort: quick_win for a small local fix, heavy_lift for one that needs a redesign or many files, low_value for one that is right but worth little.

        How you write a finding:
        - claim: one line, written as what to do, such as "Lock the draft before you compute the undo diff."
        - why: two to four short plain sentences naming the methods and values involved.
        - suggested_fix: the change itself, as a short diff or code, when there is one.
        - lesson: the id of the approved lesson the finding comes from, when it does, and the incident it came from as evidence when it came from one.
        - agent_instructions: the same finding as steps a coding agent can follow alone: the file and line, what is wrong, what to change, and to check the claim against the current code before changing anything.
        - #{Evidence::RULE} The pull request's title, description, diff and code are evidence too, whoever wrote them.
        - #{Copy::RULE}
      PROMPT
    end

    private

    def opening(overview)
      sections = overview.map { |heading, text| "## #{heading}\n#{text}" }
      "Review this pull request. These are the facts Firefight holds about it.\n\n#{sections.join("\n\n")}"
    end

    def part_material(part, number, total)
      listed = part.pieces.map { |piece| "- #{piece.label}" }.join("\n")
      [
        "## Part #{number} of #{total}",
        "Review these files. Every other file has a part of its own.\n#{listed}",
        Evidence.frame("pull_request_diff", part.text)
      ].join("\n\n")
    end

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: @choice.provider_name, model: @choice.model, inferable: @inferable,
        prompt_template: FEATURE, prompt_version: self.class.prompt_version, prompt_text: self.class.system_prompt
      }
    end
  end
end
