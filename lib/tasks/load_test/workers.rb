require "socket"
require "net/http"

# Runs chat shaped jobs on a Solid Queue worker with threads and on one with fibers, and says how each did. A job is a
# turn the way Halon takes one: it reads and writes the database, streams a model's answer token by token, broadcasts
# every token to the page, and calls a tool that reads the database and a provider's API between two model calls. The
# model and the provider are a server started here, which streams with delays like a real one, so nothing is spent and
# nothing leaves the machine.
module LoadTest
  module Workers
    QUEUE = "load_test".freeze
    TABLE = "load_test_turns".freeze
    APP_NAME = "firefight-load-test".freeze
    MODEL = "load-test".freeze
    SAMPLE_EVERY = 0.1
    GIVE_UP_AFTER = 15.minutes

    Settings = Data.define(:jobs, :configs, :first_token_ms, :tokens, :token_ms, :tool_ms, :rounds) do
      def self.from_env
        new(
          jobs: Integer(ENV.fetch("JOBS", 100)),
          configs: ENV.fetch("CONFIGS", "threads:3,fibers:25").split(",").map { |each| Config.parse(each) },
          first_token_ms: Integer(ENV.fetch("FIRST_TOKEN_MS", 600)), tokens: Integer(ENV.fetch("TOKENS", 60)),
          token_ms: Integer(ENV.fetch("TOKEN_MS", 30)), tool_ms: Integer(ENV.fetch("TOOL_MS", 300)), rounds: Integer(ENV.fetch("ROUNDS", 1))
        )
      end
    end

    # One worker to measure, such as threads:3 (what main runs) or fibers:25.
    Config = Data.define(:kind, :size) do
      def self.parse(text)
        kind, size = text.strip.split(":")
        raise ArgumentError, "#{text} is not threads:N or fibers:N" unless %w[threads fibers].include?(kind) && size.to_i.positive?

        new(kind: kind.to_sym, size: size.to_i)
      end

      def fibers? = kind == :fibers

      def label = "#{kind}: #{size}"

      def worker = { queues: QUEUE, kind => size, processes: 1, polling_interval: 0.1 }
    end

    Result = Data.define(:config, :jobs, :failed, :seconds, :total, :turn, :first_token, :connections, :held, :waiting, :rss_mb, :errors)

    class Turn < ApplicationRecord
      self.table_name = TABLE
    end

    # Reads the database and a provider's API, as a tool of Halon's does.
    class ReadService < RubyLLM::Tool
      description "Reads a service's recent errors."
      parameter :service, description: "The service's name"

      def initialize(address) = @address = address

      def execute(service:)
        seen = Turn.where.not(finished_at: nil).count
        answer = Net::HTTP.get(URI("#{@address}/tool?service=#{CGI.escape(service)}"))
        "#{answer} (#{seen} turns finished so far)"
      end
    end

    class TurnJob < ApplicationJob
      queue_as QUEUE

      QUESTION = "Why is checkout failing?".freeze
      SAVE_EVERY = 10

      def perform(turn_id, address)
        turn = Turn.find(turn_id)
        turn.update!(started_at: now)
        answer = +""
        pool = Turn.connection_pool
        held = false
        waiting = 0
        chat = RubyLLM.chat(model: MODEL, provider: :ollama, assume_model_exists: true).with_tools(ReadService.new(address))
        chat.ask(QUESTION) do |chunk|
          # Between its own queries, while the model streams, a turn should hold no connection.
          held ||= pool.active_connection?.present?
          waiting = [ waiting, pool.stat[:waiting] ].max
          next if chunk.content.blank?

          turn.update_columns(first_token_at: now) if answer.empty?
          answer << chunk.content
          ActionCable.server.broadcast("#{QUEUE}:#{turn.id}", { text: chunk.content })
          turn.update_columns(answer: answer) if (answer.count(" ") % SAVE_EVERY).zero?
        end
        turn.update!(answer: answer, finished_at: now, held_connection: held, pool_waiting: waiting)
      rescue StandardError => error
        Turn.where(id: turn_id).update_all(error: "#{error.class}: #{error.message}".truncate(500), finished_at: now)
      end

      private

      def now = Process.clock_gettime(Process::CLOCK_REALTIME)
    end

    # The model and the provider. A chat completion streams after first_token_ms, a tool call while the turn has had
    # fewer than rounds tool results, and the answer otherwise, a token every token_ms. A tool read answers after tool_ms.
    class FakeModel
      attr_reader :address

      def initialize(settings) = @settings = settings

      def start
        server = TCPServer.new("127.0.0.1", 0)
        @address = "http://127.0.0.1:#{server.addr[1]}"
        @pid = fork do
          Signal.trap("TERM") { exit!(0) }
          loop { Thread.new(server.accept) { |socket| answer(socket) } }
        end
        server.close
        self
      end

      def stop
        Process.kill("TERM", @pid)
        Process.wait(@pid)
      end

      private

      def answer(socket)
        method, path = socket.gets.to_s.split
        headers = {}
        while (line = socket.gets) && line != "\r\n"
          name, value = line.split(":", 2)
          headers[name.downcase] = value.strip
        end
        body = socket.read(headers["content-length"].to_i)
        if method == "POST" && path.end_with?("/chat/completions")
          stream(socket, JSON.parse(body))
        else
          sleep(@settings.tool_ms / 1000.0)
          respond(socket, "application/json", { errors: 3, last: "upstream timed out" }.to_json)
        end
      rescue IOError, SystemCallError
        nil
      ensure
        socket.close
      end

      def respond(socket, type, body)
        socket.write("HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      end

      def stream(socket, request)
        socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
        sleep(@settings.first_token_ms / 1000.0)
        tool_results = request["messages"].count { |message| message["role"] == "tool" }
        if tool_results < @settings.rounds
          event(socket, { tool_calls: [ { index: 0, id: "call_#{tool_results}", type: "function",
                                          function: { name: request["tools"].first.dig("function", "name"), arguments: { service: "checkout" }.to_json } } ] }, "tool_calls")
        else
          @settings.tokens.times do |index|
            event(socket, { content: "word#{index} " }, nil)
            sleep(@settings.token_ms / 1000.0)
          end
          event(socket, {}, "stop")
        end
        chunk(socket, "data: [DONE]\n\n")
        socket.write("0\r\n\r\n")
      end

      def event(socket, delta, finish)
        payload = { id: "load-test", object: "chat.completion.chunk", created: Time.now.to_i, model: MODEL,
                    choices: [ { index: 0, delta: { role: "assistant", **delta }, finish_reason: finish } ] }
        payload[:usage] = { prompt_tokens: 900, completion_tokens: @settings.tokens, total_tokens: 900 + @settings.tokens } if finish
        chunk(socket, "data: #{payload.to_json}\n\n")
      end

      def chunk(socket, data) = socket.write("#{data.bytesize.to_s(16)}\r\n#{data}\r\n")
    end

    class << self
      def run!(settings = Settings.from_env)
        raise "The load test runs against a local database only, never in production." if Rails.env.production?

        model = FakeModel.new(settings).start
        RubyLLM.configure { |config| config.ollama_api_base = "#{model.address}/v1" }
        create_table
        say "#{settings.jobs} turns per worker, each #{settings.rounds} tool call and #{settings.tokens} tokens, against #{model.address}"
        results = settings.configs.map { |config| measure(config, settings, model.address) }
        puts
        puts table(results)
        results.each do |result|
          result.errors.each { |error, count| say "#{result.config.label} failed #{count} turns with #{error}" }
        end
      ensure
        model&.stop
        drop_table
        SolidQueue::Job.where(queue_name: QUEUE).destroy_all
      end

      private

      def measure(config, settings, address)
        Turn.delete_all
        SolidQueue::Job.where(queue_name: QUEUE).destroy_all
        supervisor = start_supervisor(config)
        workers = wait_for_workers(supervisor)
        say "#{config.label}: worker #{workers.join(', ')} is up, queueing #{settings.jobs} turns"

        started = Process.clock_gettime(Process::CLOCK_REALTIME)
        ids = Turn.insert_all!(Array.new(settings.jobs) { { enqueued_at: started } }, returning: :id).rows.flatten
        ActiveJob.perform_all_later(ids.map { |id| TurnJob.new(id, address) })
        peaks = sample_until_done(settings.jobs, workers)
        result(config, peaks)
      ensure
        stop_supervisor(supervisor) if supervisor
      end

      # The worker runs in a process of its own, as bin/jobs runs it. The run on threads keeps Rails' state per thread,
      # as main does, so it measures the configuration this branch replaces.
      def start_supervisor(config)
        fork do
          ENV["PGAPPNAME"] = APP_NAME
          ActiveSupport::IsolatedExecutionState.isolation_level = config.fibers? ? :fiber : :thread
          SolidQueue.supervisor_pidfile = nil
          SolidQueue::Supervisor.clear_hooks
          SolidQueue::Supervisor.start(workers: [ config.worker ], only_work: true, skip_recurring: true)
          exit!(0)
        end
      end

      def wait_for_workers(supervisor)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
        loop do
          parent = SolidQueue::Process.find_by(pid: supervisor)
          workers = parent && SolidQueue::Process.where(kind: "Worker", supervisor_id: parent.id).pluck(:pid)
          return workers if workers.present?
          raise "The worker did not start within a minute, see log/#{Rails.env}.log" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          sleep SAMPLE_EVERY
        end
      end

      def stop_supervisor(supervisor)
        Process.kill("TERM", supervisor)
        Process.wait(supervisor)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end

      def sample_until_done(jobs, workers)
        peaks = Hash.new(0)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + GIVE_UP_AFTER
        # A job that failed before it could note so on its turn, such as when the database refused a connection, still
        # ends the wait.
        until Turn.where.not(finished_at: nil).count + failed_jobs.size >= jobs
          raise "The turns did not finish within #{GIVE_UP_AFTER.inspect}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          connections.each { |database, open| peaks[database] = [ peaks[database], open ].max }
          peaks[:rss_kb] = [ peaks[:rss_kb], workers.sum { |pid| rss_kb(pid) } ].max
          sleep SAMPLE_EVERY
        end
        peaks
      end

      # Connections the worker's process holds open, by database. A pool opens one only when every open one is in use,
      # so this is the most the worker needed at once.
      def connections
        names = databases
        rows = ActiveRecord::Base.with_connection do |connection|
          connection.select_rows(ActiveRecord::Base.sanitize_sql_array([
            "SELECT datname, count(*) FROM pg_stat_activity WHERE application_name = ? AND datname IN (?) GROUP BY datname", APP_NAME, names.values
          ]))
        end
        counts = rows.to_h
        names.transform_values { |database| counts.fetch(database, 0) }
      end

      def databases
        @databases ||= %w[primary queue cable].filter_map do |name|
          config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: name)
          [ name.to_sym, config.database ] if config
        end.to_h
      end

      def rss_kb(pid)
        status = "/proc/#{pid}/status"
        return File.read(status)[/VmRSS:\s+(\d+)/, 1].to_i if File.exist?(status)

        `ps -o rss= -p #{Integer(pid)}`.to_i
      end

      def failed_jobs
        SolidQueue::FailedExecution.joins(:job).where(solid_queue_jobs: { queue_name: QUEUE }).pluck(:error)
                                   .map { |error| "#{JSON.parse(error)['exception_class']} (the job failed)" }
      end

      def result(config, peaks)
        everything = Turn.all.to_a
        turns = everything.select(&:finished_at)
        errors = turns.filter_map(&:error) + failed_jobs
        Result.new(
          config: config, jobs: everything.size, failed: errors.size,
          seconds: (turns.map(&:finished_at).max || Process.clock_gettime(Process::CLOCK_REALTIME)) - everything.map(&:enqueued_at).min,
          total: spread(turns.map { |turn| turn.finished_at - turn.enqueued_at }),
          turn: spread(turns.filter_map { |turn| turn.finished_at - turn.started_at if turn.started_at }),
          first_token: spread(turns.filter_map { |turn| turn.first_token_at - turn.started_at if turn.first_token_at }),
          connections: peaks.slice(*databases.keys), held: turns.count(&:held_connection), waiting: turns.map(&:pool_waiting).max.to_i,
          rss_mb: (peaks[:rss_kb] / 1024.0).round, errors: errors.tally
        )
      end

      def spread(values)
        sorted = values.sort
        return {} if sorted.empty?

        { p50: sorted[(sorted.size * 0.5).floor], p95: sorted[[ (sorted.size * 0.95).ceil - 1, 0 ].max], max: sorted.last }
      end

      def table(results)
        rows = results.map do |result|
          [
            result.config.label, "#{result.jobs - result.failed}/#{result.jobs}", format("%.1f", result.jobs / result.seconds),
            seconds(result.total), seconds(result.turn), seconds(result.first_token),
            result.connections.map { |database, count| "#{database} #{count}" }.join(", "), result.held, result.waiting, result.rss_mb
          ]
        end
        header = [ "Worker", "Done", "Jobs/s", "Queued to done p50 / p95 / max", "Turn p50 / p95 / max", "First token p50 / p95 / max",
                   "Peak open connections", "Turns holding a connection while streaming", "Most jobs waiting for a connection", "Peak RSS MB" ]
        [ header, header.map { "---" }, *rows ].map { |row| "| #{row.join(' | ')} |" }.join("\n")
      end

      def seconds(spread) = spread.empty? ? "-" : spread.values_at(*spread.keys).map { |value| format("%.1fs", value) }.join(" / ")

      def say(text) = puts("[load_test] #{text}")

      def create_table
        ActiveRecord::Base.with_connection do |connection|
          connection.create_table(TABLE, if_not_exists: true) do |table|
            table.float :enqueued_at, null: false
            table.float :started_at
            table.float :first_token_at
            table.float :finished_at
            table.text :answer
            table.text :error
            table.boolean :held_connection, null: false, default: false
            table.integer :pool_waiting, null: false, default: 0
          end
        end
        Turn.reset_column_information
      end

      def drop_table
        ActiveRecord::Base.with_connection { |connection| connection.drop_table(TABLE, if_exists: true) }
      end
    end
  end
end
