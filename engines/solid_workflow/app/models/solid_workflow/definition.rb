module SolidWorkflow
  # A workflow kept as data rather than as a Ruby class: its steps, the edges between them and the outputs it hands
  # back. Each step has a stable id that never changes and a name later steps refer to it by. An edge may carry a
  # route, and it carries on only when the step it leaves took that route. The interpreter runs a snapshot of one, so
  # changing the source never changes a run already going.
  class Definition
    KIND_BRANCH = "branch".freeze
    KIND_DELAY = "delay".freeze
    KIND_WAIT_FOR_EVENT = "wait_for_event".freeze
    KIND_FOR_EACH = "for_each".freeze
    KIND_JOIN = "join".freeze
    KIND_RUN_WORKFLOW = "run_workflow".freeze
    # Ends the run, as succeeded leaving every step that has not run yet, or as failed with a reason.
    KIND_STOP = "stop".freeze
    CONTROL_KINDS = [ KIND_BRANCH, KIND_DELAY, KIND_WAIT_FOR_EVENT, KIND_FOR_EACH, KIND_JOIN, KIND_RUN_WORKFLOW, KIND_STOP ].freeze
    STOP_SUCCEEDED = "succeeded".freeze
    STOP_FAILED = "failed".freeze
    STOP_OUTCOMES = [ STOP_SUCCEEDED, STOP_FAILED ].freeze
    # A stop's config: how the run ends and why.
    CONFIG_OUTCOME = "outcome".freeze
    CONFIG_REASON = "reason".freeze
    # Kinds that park the step and wake it later, so their time limit is a deadline rather than a cap on one attempt.
    WAITING_KINDS = [ KIND_DELAY, KIND_WAIT_FOR_EVENT, KIND_FOR_EACH, KIND_RUN_WORKFLOW ].freeze

    ON_FAILURE_STOP = "stop".freeze
    ON_FAILURE_CONTINUE = "continue".freeze
    ON_FAILURE_ERROR_ROUTE = "error_route".freeze
    ON_FAILURE = [ ON_FAILURE_STOP, ON_FAILURE_CONTINUE, ON_FAILURE_ERROR_ROUTE ].freeze
    # Failures the run carries on past, so they never fail it.
    TOLERATED_FAILURES = [ ON_FAILURE_CONTINUE, ON_FAILURE_ERROR_ROUTE ].freeze

    ROUTE_ERROR = "error".freeze
    ROUTE_RECEIVED = "received".freeze
    ROUTE_TIMED_OUT = "timed_out".freeze

    # What each control step hands back, so a later step can name a field that will be there.
    OUTPUT_ROUTE = "route".freeze
    OUTPUT_WAITED_UNTIL = "waited_until".freeze
    OUTPUT_OUTCOME = "outcome".freeze
    OUTPUT_EVENT = "event".freeze
    OUTPUT_COUNT = "count".freeze
    OUTPUT_RESULTS = "results".freeze
    OUTPUT_FIRST = "first".freeze
    OUTPUT_OUTPUT = "output".freeze
    OUTPUT_STEPS = "steps".freeze
    OUTPUT_REASON = "reason".freeze
    OUTPUT_FIELDS = {
      KIND_BRANCH => [ OUTPUT_ROUTE ],
      KIND_STOP => [ OUTPUT_OUTCOME, OUTPUT_REASON ],
      KIND_DELAY => [ OUTPUT_WAITED_UNTIL ],
      KIND_WAIT_FOR_EVENT => [ OUTPUT_OUTCOME, OUTPUT_EVENT ],
      KIND_FOR_EACH => [ OUTPUT_COUNT, OUTPUT_RESULTS ],
      KIND_JOIN => [ OUTPUT_STEPS, OUTPUT_FIRST, OUTPUT_OUTPUT ]
    }.freeze

    JOIN_ALL = "all".freeze
    JOIN_FIRST = "first".freeze
    JOIN_MODES = [ JOIN_ALL, JOIN_FIRST ].freeze

    # Keys of a for each that belong to the steps inside it, so they are filled once per item and never for the loop.
    BODY_KEYS = %w[steps edges outputs].freeze

    STEP_ID = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\z/
    STEP_NAME = /\A[a-z][a-z0-9_]{0,63}\z/
    ROUTE_NAME = /\A[a-z][a-z0-9_]{0,63}\z/
    DELAY_UNITS = { "seconds" => 1, "minutes" => 60, "hours" => 3600, "days" => 86_400 }.freeze
    TIME_OF_DAY = /\A([01]?\d|2[0-3]):([0-5]\d)\z/
    MAX_CONCURRENCY = 50
    MAX_ATTEMPTS = 10
    BACKOFFS = %w[exponential linear fixed].freeze

    attr_reader :steps, :edges, :outputs

    def initialize(data, action_kinds: [])
      data = (data || {}).to_h.deep_stringify_keys
      @steps = Array(data["steps"]).map { |step| step.is_a?(Hash) ? step : {} }
      @edges = Array(data["edges"]).map { |edge| edge.is_a?(Hash) ? edge : {} }
      @outputs = data["outputs"].is_a?(Hash) ? data["outputs"] : {}
      @action_kinds = action_kinds.map(&:to_s)
    end

    def kinds = CONTROL_KINDS + @action_kinds

    def step(id) = steps.find { |step| step["id"] == id }

    def incoming(id) = edges.select { |edge| edge["to"] == id }.map { |edge| { "from" => edge["from"], "route" => edge["route"].presence } }

    def body(step)
      config = step["config"].is_a?(Hash) ? step["config"] : {}
      Definition.new(config.slice(*BODY_KEYS), action_kinds: @action_kinds)
    end

    # Every step name in the definition and inside each for each, since a name is unique across all of them.
    def all_names = steps.flat_map { |step| [ step["name"], *(step["kind"] == KIND_FOR_EACH ? body(step).all_names : []) ] }

    # Each problem as a sentence. None means the interpreter can run it.
    def problems
      found = []
      found << "A workflow needs at least one step." if steps.empty?
      found.concat(step_problems)
      found.concat(edge_problems)
      found.concat(cycle_problems)
      names = all_names.compact
      duplicates = names.tally.select { |_name, count| count > 1 }.keys
      found << "Step names must be unique, and #{duplicates.to_sentence} is used more than once." if duplicates.any?
      found.uniq
    end

    private

    def step_problems
      ids = steps.map { |step| step["id"] }
      duplicates = ids.compact.tally.select { |_id, count| count > 1 }.keys
      found = duplicates.any? ? [ "Step ids must be unique, and #{duplicates.to_sentence} is used more than once." ] : []
      steps.each { |step| found.concat(problems_of(step)) }
      found
    end

    def problems_of(step)
      label = step["name"].presence || step["id"].presence || "A step"
      return [ "#{label} needs an id of letters, numbers, dashes and underscores." ] unless step["id"].to_s.match?(STEP_ID)
      return [ "#{label} needs a name of lowercase letters, numbers and underscores, starting with a letter." ] unless step["name"].to_s.match?(STEP_NAME)
      return [ "#{label} is a #{step['kind'].presence || 'blank'} step, which is not a kind of step." ] unless kinds.include?(step["kind"])

      settings_problems(step, label) + kind_problems(step, label)
    end

    def settings_problems(step, label)
      found = []
      timeout = step["timeout_seconds"]
      found << "#{label} needs its time limit as a whole number of seconds above zero." unless timeout.nil? || (timeout.is_a?(Integer) && timeout.positive?)
      found << "#{label} says what happens when it fails in a way that is not stop, continue or take the error route." unless step["on_failure"].nil? || ON_FAILURE.include?(step["on_failure"])
      if step["on_failure"] == ON_FAILURE_ERROR_ROUTE && edges.none? { |edge| edge["from"] == step["id"] && edge["route"] == ROUTE_ERROR }
        found << "#{label} takes the error route when it fails, so it needs an error route to take."
      end
      found.concat(retry_problems(step["retry"], label))
    end

    def retry_problems(retry_config, label)
      return [] if retry_config.nil?
      return [ "#{label} needs its retries as settings." ] unless retry_config.is_a?(Hash)

      found = []
      attempts = retry_config["max_attempts"]
      found << "#{label} can try between 1 and #{MAX_ATTEMPTS} times." unless attempts.nil? || (attempts.is_a?(Integer) && attempts.between?(1, MAX_ATTEMPTS))
      found << "#{label} backs off in a way that is not exponential, linear or fixed." unless retry_config["backoff"].nil? || BACKOFFS.include?(retry_config["backoff"])
      found
    end

    def kind_problems(step, label)
      config = step["config"].is_a?(Hash) ? step["config"] : {}
      case step["kind"]
      when KIND_BRANCH then branch_problems(step, config, label)
      when KIND_DELAY then delay_problems(config, label)
      when KIND_WAIT_FOR_EVENT then wait_problems(step, config, label)
      when KIND_FOR_EACH then for_each_problems(config, label)
      when KIND_JOIN then join_problems(step, config, label)
      when KIND_RUN_WORKFLOW then config["workflow"].present? ? [] : [ "#{label} needs the workflow it runs." ]
      when KIND_STOP then stop_problems(config, label)
      else []
      end
    end

    def stop_problems(config, label)
      outcome = config[CONFIG_OUTCOME].presence || STOP_SUCCEEDED
      return [ "#{label} ends the run as succeeded or failed." ] unless STOP_OUTCOMES.include?(outcome) || placeholder?(outcome)
      return [ "#{label} says why it fails the run." ] if outcome == STOP_FAILED && config[CONFIG_REASON].to_s.strip.empty?

      []
    end

    def branch_problems(step, config, label)
      routes = config["routes"]
      return [ "#{label} needs at least one route with a condition." ] unless routes.is_a?(Array) && routes.any?

      found = []
      names = routes.map { |route| route.is_a?(Hash) ? route["route"] : nil }
      found << "#{label} needs each route named in lowercase letters, numbers and underscores." unless names.all? { |name| name.to_s.match?(ROUTE_NAME) }
      found << "#{label} needs a condition on each route." unless routes.all? { |route| route.is_a?(Hash) && Condition.well_formed?(route["when"]) }
      found << "#{label} needs each route named once." unless names.uniq.size == names.size
      otherwise = config["otherwise"]
      found << "#{label} needs its otherwise route named in lowercase letters, numbers and underscores." unless otherwise.nil? || otherwise.to_s.match?(ROUTE_NAME)
      taken = names + [ otherwise ].compact + [ ROUTE_ERROR ]
      edges.select { |edge| edge["from"] == step["id"] && edge["route"].present? }.each do |edge|
        found << "#{label} has no route called #{edge['route']}." unless taken.include?(edge["route"])
      end
      found
    end

    def delay_problems(config, label)
      units = DELAY_UNITS.keys.select { |unit| config.key?(unit) }
      ways = [ units.any?, config.key?("until"), config.key?("at") ].count(true)
      return [ "#{label} waits either a length of time, until a time of day or until a moment, and needs exactly one." ] unless ways == 1

      if units.any?
        return [ "#{label} needs its length of time as numbers." ] unless units.all? { |unit| config[unit].is_a?(Numeric) || placeholder?(config[unit]) }
      elsif config.key?("until")
        return [ "#{label} waits until a time of day written as 09:00." ] unless config["until"].to_s.match?(TIME_OF_DAY) || placeholder?(config["until"])
        return [ "#{label} names a time zone that does not exist." ] unless config["time_zone"].nil? || ActiveSupport::TimeZone[config["time_zone"].to_s] || placeholder?(config["time_zone"])
      end
      []
    end

    def wait_problems(step, config, label)
      found = []
      found << "#{label} needs the event it waits for." if config["event"].blank?
      found << "#{label} needs a time limit, since an event may never come." if step["timeout_seconds"].nil?
      found
    end

    def for_each_problems(config, label)
      found = []
      found << "#{label} needs the list it goes through." if config["items"].nil?
      concurrency = config["concurrency"]
      unless concurrency.nil? || (concurrency.is_a?(Integer) && concurrency.between?(1, MAX_CONCURRENCY))
        found << "#{label} runs between 1 and #{MAX_CONCURRENCY} items at once."
      end
      inside = Definition.new(config.slice(*BODY_KEYS), action_kinds: @action_kinds)
      found.concat(inside.send(:step_problems)).concat(inside.send(:edge_problems)).concat(inside.send(:cycle_problems))
      found << "#{label} needs at least one step inside it." if inside.steps.empty?
      found
    end

    def join_problems(step, config, label)
      found = []
      found << "#{label} joins either all of its routes or the first, and needs one of them." unless config["mode"].nil? || JOIN_MODES.include?(config["mode"])
      found << "#{label} needs at least two routes into it." if incoming(step["id"]).size < 2
      found
    end

    def edge_problems
      ids = steps.map { |step| step["id"] }
      found = []
      edges.each do |edge|
        unless ids.include?(edge["from"]) && ids.include?(edge["to"])
          found << "A connection names a step that is not in the workflow."
          next
        end
        found << "A step cannot connect to itself." if edge["from"] == edge["to"]
        found << "A connection's route is named in lowercase letters, numbers and underscores." unless edge["route"].blank? || edge["route"].to_s.match?(ROUTE_NAME)
      end
      keys = edges.map { |edge| [ edge["from"], edge["to"], edge["route"].presence ] }
      found << "Two steps are connected the same way twice." unless keys.uniq.size == keys.size
      found
    end

    def cycle_problems
      sources = steps.to_h { |step| [ step["id"], incoming(step["id"]).map { |edge| edge["from"] } ] }
      visited = Set.new
      visiting = Set.new
      cyclic = false
      visit = lambda do |id|
        return if visited.include?(id) || cyclic
        return cyclic = true if visiting.include?(id)

        visiting << id
        Array(sources[id]).each { |source| visit.call(source) }
        visiting.delete(id)
        visited << id
      end
      sources.each_key { |id| visit.call(id) }
      cyclic ? [ "The steps loop back on themselves, so the workflow would never end." ] : []
    end

    def placeholder?(value) = value.is_a?(String) && value.include?("{{")
  end
end
