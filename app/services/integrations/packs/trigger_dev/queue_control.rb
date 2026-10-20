module Integrations
  module Packs
    class TriggerDev
      # Holding runs back and letting more through: pausing and resuming a queue or a concurrency limit, and overriding
      # how many of its runs execute at once or putting that back to what the code declares (pause_queue_v1,
      # override_queue_concurrency_v1, reset_queue_concurrency_v1 and the concurrency-limits forms), as Trigger.dev's
      # OpenAPI spec gives them (triggerdotdev/trigger.dev, docs/v3-openapi.yaml). Runs already executing finish either way.
      module QueueControl
        # How a queue is named (retrieve_queue_v1): its id, a task's identifier for the task's own queue, or a custom
        # queue's name.
        QUEUE_TYPES = %w[id task custom].freeze
        QUEUE_ID_PREFIX = "queue_".freeze
        PAUSE = "pause".freeze
        RESUME = "resume".freeze
        MOST = 100_000
        QUEUE = {
          "queue" => { "type" => "string", "description" => "The queue, by its id starting queue_, a task's identifier for the task's own queue, " \
                                                            "or a custom queue's name, as list_queues shows it" },
          "type" => { "type" => "string", "enum" => QUEUE_TYPES,
                      "description" => "How queue is named: id, task or custom (optional, id for one starting queue_, else task)" }
        }.freeze
        LIMIT = { "limit" => { "type" => "string", "description" => "The concurrency limit, by its name, as list_queues shows it" } }.freeze

        def self.included(pack)
          pack.tool :pause_queue,
                    summary: "Pauses a Trigger.dev queue so no new run starts on it.",
                    description: "Pause a queue, so none of its waiting runs starts until it is resumed, such as a task that floods " \
                                 "something downstream. Runs already executing finish. Runs keep queueing while it is paused",
                    params_schema: { "type" => "object", "properties" => QUEUE, "required" => [ "queue" ] },
                    read_only: false

          pack.tool :resume_queue,
                    summary: "Resumes a paused Trigger.dev queue.",
                    description: "Resume a paused queue, so its waiting runs start again within its limit",
                    params_schema: { "type" => "object", "properties" => QUEUE, "required" => [ "queue" ] },
                    read_only: false

          pack.tool :override_queue_concurrency,
                    summary: "Sets how many runs of a Trigger.dev queue execute at once, over its code.",
                    description: "Set how many runs of a queue execute at once, over the limit its code declares, until it is reset, " \
                                 "such as more to drain a backlog or fewer to spare something downstream. At most the environment's own limit",
                    params_schema: { "type" => "object",
                                     "properties" => QUEUE.merge("concurrency" => { "type" => "integer", "description" => "How many runs at once, 0 to #{MOST}" }),
                                     "required" => %w[queue concurrency] },
                    read_only: false

          pack.tool :reset_queue_concurrency,
                    summary: "Puts a Trigger.dev queue's limit back to what its code declares.",
                    description: "Take away a queue's override, so its limit is the one its code declares again",
                    params_schema: { "type" => "object", "properties" => QUEUE, "required" => [ "queue" ] },
                    read_only: false

          pack.tool :pause_concurrency_limit,
                    summary: "Pauses a Trigger.dev concurrency limit so no run holding it starts.",
                    description: "Pause a concurrency limit, so no waiting run that holds it starts until it is resumed, in every task " \
                                 "that holds it. Runs already executing finish, and its bounds are kept",
                    params_schema: { "type" => "object", "properties" => LIMIT, "required" => [ "limit" ] },
                    read_only: false

          pack.tool :resume_concurrency_limit,
                    summary: "Resumes a paused Trigger.dev concurrency limit.",
                    description: "Resume a paused concurrency limit, so its waiting runs start again within its bounds",
                    params_schema: { "type" => "object", "properties" => LIMIT, "required" => [ "limit" ] },
                    read_only: false

          pack.tool :override_concurrency_limit,
                    summary: "Sets a Trigger.dev concurrency limit's bounds over its code.",
                    description: "Set a concurrency limit's total, its bound for each concurrency key, or both, over what its code " \
                                 "declares, until it is reset. Each at most the environment's own limit",
                    params_schema: {
                      "type" => "object",
                      "properties" => LIMIT.merge(
                        "total" => { "type" => "integer", "description" => "How many runs holding it execute at once in all, 0 to #{MOST} (optional)" },
                        "per_key" => { "type" => "integer", "description" => "How many execute at once for each concurrency key, 0 to #{MOST} (optional)" }
                      ),
                      "required" => [ "limit" ]
                    },
                    read_only: false

          pack.tool :reset_concurrency_limit,
                    summary: "Puts a Trigger.dev concurrency limit back to what its code declares.",
                    description: "Take away a concurrency limit's override, so its bounds are the ones its code declares again",
                    params_schema: { "type" => "object", "properties" => LIMIT, "required" => [ "limit" ] },
                    read_only: false
        end

        # The queue's id is in the answer, so a pause made without asking is resumed by it, and only when it was not
        # paused before.
        def pause_queue(environment_row:, arguments:)
          name, type = queue_of(arguments)
          api = api(environment_row)
          queue = api.queue(name, type)
          fail!("Queue #{queue['name']} is already paused.") if queue["paused"]

          paused = changing("pause queue #{name}") { api.pause_queue(name, type, PAUSE) }
          Telemetry.result("Queue #{paused['name'] || name} is paused, so none of its #{paused['queued'] || queue['queued']} waiting runs starts until it is " \
                           "resumed. The #{paused['running'] || queue['running']} executing finish. #{no_page}", link: nil, facts: { "queue" => paused["id"] || queue["id"] })
        end

        def resume_queue(environment_row:, arguments:)
          name, type = queue_of(arguments)
          api = api(environment_row)
          queue = api.queue(name, type)
          fail!("Queue #{queue['name']} is not paused.") unless queue["paused"]

          resumed = changing("resume queue #{name}") { api.pause_queue(name, type, RESUME) }
          Telemetry.result("Queue #{resumed['name'] || name} is resumed, so its #{resumed['queued'] || queue['queued']} waiting runs start within its limit. #{no_page}", link: nil)
        end

        def override_queue_concurrency(environment_row:, arguments:)
          name, type = queue_of(arguments)
          count = bound(arguments["concurrency"], "concurrency")
          fail!("Say how many runs of the queue execute at once, as concurrency.") if count.nil?

          queue = changing("override queue #{name}") { api(environment_row).override_queue_concurrency(name, type, count) }
          base = queue.dig("concurrency", "base")
          Telemetry.result("Queue #{queue['name'] || name} runs at most #{count} at once until it is reset#{", over the #{base} its code declares" if base}. #{no_page}", link: nil)
        end

        def reset_queue_concurrency(environment_row:, arguments:)
          name, type = queue_of(arguments)
          queue = changing("reset queue #{name}") { api(environment_row).reset_queue_concurrency(name, type) }
          Telemetry.result("Queue #{queue['name'] || name} is back to the limit its code declares, #{queue.dig('concurrency', 'base') || queue['concurrencyLimit'] || 'none'}. #{no_page}",
                           link: nil)
        end

        def pause_concurrency_limit(environment_row:, arguments:)
          name = limit_of(arguments)
          api = api(environment_row)
          fail!("Concurrency limit #{name} is already paused.") if api.concurrency_limit(name)["paused"]

          paused = changing("pause concurrency limit #{name}") { api.pause_concurrency_limit(name, PAUSE) }
          Telemetry.result("Concurrency limit #{name} is paused, so none of its #{paused['queued']} waiting runs starts until it is resumed. The " \
                           "#{paused['running']} executing finish. #{no_page}".squish, link: nil, facts: { "limit" => name })
        end

        def resume_concurrency_limit(environment_row:, arguments:)
          name = limit_of(arguments)
          api = api(environment_row)
          fail!("Concurrency limit #{name} is not paused.") unless api.concurrency_limit(name)["paused"]

          changing("resume concurrency limit #{name}") { api.pause_concurrency_limit(name, RESUME) }
          Telemetry.result("Concurrency limit #{name} is resumed, so its waiting runs start within its bounds. #{no_page}", link: nil)
        end

        def override_concurrency_limit(environment_row:, arguments:)
          name = limit_of(arguments)
          total = bound(arguments["total"], "total")
          per_key = bound(arguments["per_key"], "per_key")
          fail!("Give total, per_key or both.") if total.nil? && per_key.nil?

          limit = changing("override concurrency limit #{name}") { api(environment_row).override_concurrency_limit(name, total: total, per_key: per_key) }
          Telemetry.result("Concurrency limit #{name} now allows #{limit_bounds(limit, total, per_key)} until it is reset. #{no_page}", link: nil)
        end

        def reset_concurrency_limit(environment_row:, arguments:)
          name = limit_of(arguments)
          limit = changing("reset concurrency limit #{name}") { api(environment_row).reset_concurrency_limit(name) }
          Telemetry.result("Concurrency limit #{name} is back to what its code declares, #{limit_bounds(limit, nil, nil)}. #{no_page}", link: nil)
        end

        private

        def queue_of(arguments)
          name = arguments["queue"].to_s.strip
          fail!("Say which queue, by its id, a task's identifier or a custom queue's name. list_queues shows them.") if name.empty?

          type = arguments["type"].to_s.strip.presence || (name.start_with?(QUEUE_ID_PREFIX) ? "id" : "task")
          fail!("type must be one of #{QUEUE_TYPES.join(', ')}.") unless QUEUE_TYPES.include?(type)

          [ name, type ]
        end

        def limit_of(arguments)
          arguments["limit"].to_s.strip.presence || fail!("Say which concurrency limit, by its name. list_queues shows them.")
        end

        def bound(value, name)
          return if value.nil? || value.to_s.strip.empty?

          # Integer() truncates a Float, so a fraction is refused rather than rounded down.
          count = value.is_a?(Float) && !(value.finite? && value == value.floor) ? nil : Integer(value, exception: false)
          fail!("#{name} must be a whole number from 0 to #{MOST}.") unless count&.between?(0, MOST)

          count
        end

        def limit_bounds(limit, total, per_key)
          total = limit.dig("total", "current") || total
          per_key = limit.dig("perKey", "current") || per_key
          "#{total || 'any number'} at once in all and #{per_key || 'any number'} for each key"
        end
      end
    end
  end
end
