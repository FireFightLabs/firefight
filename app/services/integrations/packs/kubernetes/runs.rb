module Integrations
  module Packs
    class Kubernetes < NativePack
      # A workload's runs as Firefight follows them. A deployment, statefulset or daemonset runs a rollout per revision,
      # from the replica sets or controller revisions kubectl rollout history reads, and a cronjob runs jobs, the ones it
      # controls (ownerReferences), while a job is its own one run. Kubernetes keeps the end of only the current rollout,
      # in a deployment's Progressing condition (NewReplicaSetAvailable when it completed, ProgressDeadlineExceeded when
      # it failed), and nothing of how an earlier one ended, so an earlier rollout has no end time. A job keeps its own
      # (startTime, completionTime, and its Complete or Failed condition). Read one run by its revision or job name and
      # each of its pods is a part, with how it stands, why it failed and its own log. (Kubernetes API reference,
      # Deployment, StatefulSet, DaemonSet, ControllerRevision, Job and Pod, and the Deployments concept page, Deployment
      # status, https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#deployment-status)
      module Runs
        WORKLOAD_RUNS = "workload_runs".freeze
        RUN_LIMIT = Capabilities::History::LIMIT
        History = Capabilities::History
        # kubectl rollout undo gives the replica set it goes back to the next revision and keeps its earlier numbers here
        # (deployment util, RevisionHistoryAnnotation), so a revision that has them was a rollback.
        REVISION_HISTORY = "deployment.kubernetes.io/revision-history".freeze
        # The label a statefulset's or daemonset's pods carry naming their controller revision (apps/v1
        # ControllerRevisionHashLabelKey).
        REVISION_HASH = "controller-revision-hash".freeze
        # What a Job carries when kubectl create job --from=cronjob started it by hand.
        INSTANTIATE = "cronjob.kubernetes.io/instantiate".freeze
        MANUAL = "manual".freeze
        PROGRESS_FAILED = "ProgressDeadlineExceeded".freeze
        # A container waiting for one of these is not going to start without a change.
        STUCK = %w[CrashLoopBackOff ImagePullBackOff ErrImagePull InvalidImageName CreateContainerConfigError CreateContainerError RunContainerError].freeze
        NO_END = "Kubernetes keeps no time for when it finished".freeze
        PODS_READ = 20

        def self.included(pack)
          pack.tool WORKLOAD_RUNS,
                    summary: "Shows a workload's recent rollouts or job runs and how each one went.",
                    description: "A workload's recent runs, newest first: a deployment's, statefulset's or daemonset's rollouts, one per " \
                                 "revision, or a cronjob's jobs, or a job's own run, each with how it went, when it started and finished, " \
                                 "how long it took, and how long finished ones usually take. Name a run, a revision number or a job's name, " \
                                 "to read it with each of its pods, how each stands, why one failed and how to read its log. Kubernetes keeps " \
                                 "the end of only the current rollout, so an earlier one has no end time",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "namespace" => NAMESPACE, "resource" => RESOURCE,
                        "run" => { "type" => "string", "description" => "Only this run, by its revision number for a rollout or its job's name for a cronjob, with each pod (optional)" },
                        "name" => { "type" => "string", "description" => "Only runs whose name contains this (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many runs (optional, #{RUN_LIMIT})" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: true
        end

        def workload_runs(environment_row:, arguments:)
          workload = find_workload(environment_row, arguments)
          limit = Capabilities::Answers.limit(arguments, RUN_LIMIT)
          run = arguments["run"].to_s.strip.delete_prefix("#").presence
          rolling = ROLLING.include?(workload[:kind].key)
          runs = rolling ? rollout_runs(environment_row, workload, run) : job_runs(environment_row, workload, run)
          what = rolling ? "the rollouts of #{label(workload)}" : "the runs of #{label(workload)}"
          result = History.result(runs, what: what, name: arguments["name"], limit: limit)
          result["content"].first["text"] = "#{result['content'].first['text']}\n#{format(CHECK_LINE, command: runs_command(workload, run))}"
          result
        end

        private

        # Each revision as a rollout, newest first, or the one asked for with its pods. Only the current one has a known
        # outcome. An earlier one was replaced, by a rollback when the revision after it went back to an older template.
        def rollout_runs(environment_row, workload, run)
          revisions = revisions_of(environment_row, workload).sort_by { |revision| revision[:number] }
          if run
            number = Integer(run.delete_prefix("revision").strip, exception: false)
            fail! "run must be a revision number, as #{WORKLOAD_RUNS} or rollout_history shows it." unless number&.positive?
          end
          runs = revisions.each_with_index.map do |revision, index|
            rollout_run(workload, revision, revisions[index + 1])
          end
          return runs unless run

          index = revisions.index { |revision| revision[:number] == number }
          fail! "#{label(workload)} has no revision #{number}. #{WORKLOAD_RUNS} shows the ones it keeps." unless index

          [ runs[index].with(parts: revision_pods(environment_row, workload, revisions[index]).map { |pod| pod_part(workload, pod, rollout: true) }) ]
        end

        def rollout_run(workload, revision, after)
          object = workload[:object]
          made = Telemetry.parse_time(revision[:created])
          earlier = revision[:source].dig("metadata", "annotations", REVISION_HISTORY).present?
          said = [ "images #{revision[:images].join(', ').presence || 'unknown'}", ("change cause #{revision[:cause]}" if revision[:cause].present?) ]
          if revision[:current]
            status, finished, detail = current_rollout(workload[:kind].key, object)
            # A rollback reuses the replica set it goes back to, which was made long before, so its start is not known.
            started = earlier ? nil : made
            said.unshift("back to an earlier template, when it began is not kept") if earlier
            said.unshift(detail) if detail
          else
            started = made
            finished = nil
            rolled_back = after && after[:source].dig("metadata", "annotations", REVISION_HISTORY).present?
            status = rolled_back ? History::CANCELLED : History::SUCCEEDED
            said.unshift(replaced_words(after, rolled_back))
          end
          History::Run.new(id: revision[:number].to_s, number: revision[:number], name: workload[:name], status: status,
                           started_at: started, finished_at: finished, detail: said.compact.join(", "))
        end

        # A revision as a deploy, read as its rollout is, from the workload already read. Only the current revision serves.
        def revision_deploy(workload, revision, after)
          run = rollout_run(workload, revision, after)
          Capabilities::Deploys::Deploy.new(id: run.id, version: revision[:number], status: run.status, live: revision[:current],
                                            started_at: run.started_at, finished_at: run.finished_at)
        end

        def replaced_words(after, rolled_back)
          return "rolled back by revision #{after[:number]}" if rolled_back
          return "replaced by revision #{after[:number]}, #{NO_END}" if after

          NO_END
        end

        # How the current rollout stands, as kubectl rollout status judges it (kubectl, polymorphichelpers rollout_status.go),
        # with when it ended where Kubernetes keeps it.
        def current_rollout(kind, object)
          spec = object["spec"].to_h
          status = object["status"].to_h
          observed = status["observedGeneration"].to_i >= object.dig("metadata", "generation").to_i
          case kind
          when DEPLOYMENT
            progressing = Array(status["conditions"]).find { |condition| condition["type"] == "Progressing" }.to_h
            return [ History::RUNNING, nil, "paused, waiting for rollout_resume" ] if spec["paused"]
            if progressing["reason"] == PROGRESS_FAILED
              return [ History::FAILED, Telemetry.parse_time(progressing["lastUpdateTime"]), progressing["message"].presence || "it did not progress in time" ]
            end

            desired = spec.fetch("replicas", 1)
            updated = status["updatedReplicas"].to_i
            done = observed && updated >= desired && status["replicas"].to_i <= updated && status["availableReplicas"].to_i >= updated
            return [ History::RUNNING, nil, "#{updated} of #{desired} pods updated, #{status['availableReplicas'].to_i} available" ] unless done

            ended = Telemetry.parse_time(progressing["lastUpdateTime"]) if progressing["reason"] == "NewReplicaSetAvailable"
            [ History::SUCCEEDED, ended, (NO_END unless ended) ]
          when STATEFULSET
            desired = spec.fetch("replicas", 1)
            done = observed && status["currentRevision"] == status["updateRevision"] && status["updatedReplicas"].to_i >= desired && status["readyReplicas"].to_i >= desired
            done ? [ History::SUCCEEDED, nil, NO_END ] : [ History::RUNNING, nil, "#{status['updatedReplicas'].to_i} of #{desired} pods updated, #{status['readyReplicas'].to_i} ready" ]
          else
            desired = status["desiredNumberScheduled"].to_i
            done = observed && status["updatedNumberScheduled"].to_i >= desired && status["numberAvailable"].to_i >= desired
            done ? [ History::SUCCEEDED, nil, NO_END ] : [ History::RUNNING, nil, "#{status['updatedNumberScheduled'].to_i} of #{desired} pods updated, #{status['numberAvailable'].to_i} available" ]
          end
        end

        # The pods of one revision: a deployment's by its replica set's pod-template-hash, a statefulset's or daemonset's
        # by the controller revision they carry.
        def revision_pods(environment_row, workload, revision)
          source = revision[:source]
          pods = pods_of(environment_row, workload)
          if workload[:kind].key == DEPLOYMENT
            hash = source.dig("metadata", "labels", POD_TEMPLATE_HASH) || source.dig("spec", "template", "metadata", "labels", POD_TEMPLATE_HASH)
            return [] if hash.blank?

            pods.select { |pod| pod.dig("metadata", "labels", POD_TEMPLATE_HASH) == hash }
          else
            names = [ source.dig("metadata", "name"), source.dig("metadata", "labels", REVISION_HASH) ].compact
            pods.select { |pod| names.include?(pod.dig("metadata", "labels", REVISION_HASH)) }
          end.sort_by { |pod| [ pod.dig("metadata", "creationTimestamp").to_s, pod.dig("metadata", "name").to_s ] }.first(PODS_READ)
        end

        # A cronjob's jobs, newest first, or a job's own run, or the one asked for with its pods.
        def job_runs(environment_row, workload, run)
          if workload[:kind].key == JOB
            fail! "#{label(workload)} is one run, called #{workload[:name]}." if run && run != workload[:name]
            return [ job_run(workload, workload[:object], parts: (job_pods(environment_row, workload, workload[:object]) if run)) ]
          end
          return jobs_of(environment_row, workload).map { |job| job_run(workload, job) } unless run

          job = begin
            api(environment_row).get("#{self.class.collection(WORKLOADS.fetch(JOB), workload[:namespace])}/#{segment(run)}")
          rescue KubernetesApi::NotFound
            nil
          end
          unless job && controlled_by?(job, workload[:object].dig("metadata", "uid"))
            fail! "#{label(workload)} has no job called #{run}. #{WORKLOAD_RUNS} shows the ones Kubernetes still keeps."
          end

          [ job_run(workload, job, parts: job_pods(environment_row, workload, job)) ]
        end

        def job_run(workload, job, parts: nil)
          status = job["status"].to_h
          failed = Array(status["conditions"]).find { |condition| condition["type"] == "Failed" && condition["status"] == "True" }
          complete = self.class.condition?(status, "Complete")
          state = if complete then History::SUCCEEDED
          elsif failed then History::FAILED
          elsif job.dig("spec", "suspend") || status["startTime"].blank? then History::QUEUED
          else History::RUNNING
          end
          ended = Telemetry.parse_time(status["completionTime"]) if complete
          ended ||= Telemetry.parse_time(failed["lastTransitionTime"]) if failed
          name = job.dig("metadata", "name")
          detail = [
            (name unless name == workload[:name]),
            ("#{failed['reason']}#{": #{failed['message']}" if failed['message'].present?}" if failed),
            ("#{status['succeeded'].to_i} pods succeeded, #{status['failed'].to_i} failed" if status["succeeded"].to_i + status["failed"].to_i > 0),
            ("#{status['active'].to_i} running" if status["active"].to_i.positive?),
            ("suspended" if job.dig("spec", "suspend")),
            ("started by hand" if job.dig("metadata", "annotations", INSTANTIATE) == MANUAL)
          ].compact.join(", ").presence
          History::Run.new(id: name, name: workload[:name], status: state,
                           started_at: Telemetry.parse_time(status["startTime"] || job.dig("metadata", "creationTimestamp")),
                           finished_at: ended, detail: detail, parts: parts&.map { |pod| pod_part(workload, pod, rollout: false) })
        end

        def job_pods(environment_row, workload, job)
          found = selector(job.dig("spec", "selector"))
          return [] if found.empty?

          api(environment_row).list("#{CORE}/namespaces/#{segment(workload[:namespace])}/pods", "labelSelector" => found).items
                              .sort_by { |pod| pod.dig("metadata", "creationTimestamp").to_s }.first(PODS_READ)
        end

        # One pod as a part. In a rollout a pod is done once it is ready, and in a job once it ran to the end. A container
        # stuck waiting, such as on CrashLoopBackOff or an image it cannot pull, is a failure, with why.
        def pod_part(workload, pod, rollout:)
          statuses = [ *Array(pod.dig("status", "initContainerStatuses")), *Array(pod.dig("status", "containerStatuses")) ]
          phase = pod.dig("status", "phase").to_s
          stuck = statuses.find { |status| STUCK.include?(status.dig("state", "waiting", "reason")) }
          ready = Array(pod.dig("status", "conditions")).find { |condition| condition["type"] == "Ready" && condition["status"] == "True" }
          ended = statuses.filter_map { |status| status.dig("state", "terminated", "finishedAt") }.max
          state = if phase == "Succeeded" then History::SUCCEEDED
          elsif phase == "Failed" || stuck then History::FAILED
          elsif phase == "Pending" then History::QUEUED
          elsif rollout && ready then History::SUCCEEDED
          else History::RUNNING
          end
          started = Telemetry.parse_time(pod.dig("status", "startTime") || pod.dig("metadata", "creationTimestamp"))
          finished = if History::FINISHED.include?(state)
            rollout && ready ? Telemetry.parse_time(ready["lastTransitionTime"]) : Telemetry.parse_time(ended)
          end
          name = pod.dig("metadata", "name")
          window = { "start" => started&.utc&.iso8601, "end" => (finished || (Time.current if started))&.utc&.iso8601 }.compact
          History::Part.new(id: name, name: "pod #{name}", status: state, started_at: started, finished_at: finished,
                            detail: pod_detail(pod, statuses, stuck),
                            log: { History::LOG_TOOL => "workload_logs", History::LOG_ARGUMENTS => { "namespace" => workload[:namespace], "pod" => name }.merge(window) })
        end

        def pod_detail(pod, statuses, stuck)
          terminated = statuses.filter_map { |status| [ status["name"], status.dig("state", "terminated") || status.dig("lastState", "terminated") ] if status.dig("state", "terminated") || status.dig("lastState", "terminated") }
          restarts = statuses.sum { |status| status["restartCount"].to_i }
          waiting = statuses.filter_map { |status| status.dig("state", "waiting", "reason") }.first
          [
            (pod.dig("status", "reason") if pod.dig("status", "reason").present?),
            ("#{stuck['name']} #{stuck.dig('state', 'waiting', 'reason')}#{": #{stuck.dig('state', 'waiting', 'message').to_s.truncate(200)}" if stuck.dig('state', 'waiting', 'message').present?}" if stuck),
            ("waiting: #{waiting}" if waiting && !stuck),
            *terminated.reject { |_name, state| state["exitCode"].to_i.zero? && state["reason"] == "Completed" }
                       .map { |container, state| "#{container} #{state['reason'] || 'stopped'}, exit code #{state['exitCode']}" },
            ("#{restarts} restarts" if restarts.positive?)
          ].compact.uniq.join(", ").presence
        end

        def runs_command(workload, run)
          target = "#{workload[:kind].key}/#{workload[:name]} -n #{workload[:namespace]}"
          case workload[:kind].key
          when *ROLLING then "kubectl rollout history #{target}#{" --revision=#{run.to_s.delete_prefix('revision').strip}" if run}"
          when CRONJOB then run ? "kubectl describe job/#{run} -n #{workload[:namespace]}" : "kubectl get jobs -n #{workload[:namespace]} --sort-by=.status.startTime"
          else "kubectl describe #{target}"
          end
        end
      end
    end
  end
end
