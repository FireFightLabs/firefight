module Integrations
  module Packs
    class Kubernetes < NativePack
      # Changes that hold a rollout or a schedule, or start a run by hand, as kubectl does them: rollout pause and resume
      # set a deployment's spec.paused (kubectl, polymorphichelpers objectpauser.go and objectresumer.go), a cronjob's
      # spec.suspend stops new runs and lets them go again (CronJob concepts, Schedule suspension), and kubectl create job
      # --from=cronjob makes a Job of the cronjob's jobTemplate, marked as started by hand and owned by the cronjob
      # (kubectl, pkg/cmd/create/create_job.go, createJobFromCronJob). Each is its own tool, so each is granted apart.
      module Controls
        PAUSE = "rollout_pause".freeze
        RESUME = "rollout_resume".freeze
        RUN_NOW = "run_cronjob_now".freeze
        SUSPEND = "suspend_cronjob".freeze
        RESUME_SCHEDULE = "resume_cronjob".freeze
        # A Job's name is a label value, at most 63 characters, so the cronjob's name is cut to leave room for the rest.
        NAME_MOST = 63
        MANUAL_SUFFIX = "-manual-".freeze
        SUFFIX_BYTES = 4

        def self.included(pack)
          cronjob = { "type" => "string", "description" => "The cronjob, as cronjob/name or a name alone" }
          deployment = { "type" => "string", "description" => "The deployment, as deployment/name or a name alone" }
          pack.tool PAUSE,
                    summary: "Pauses a deployment's rollout where it stands.",
                    description: "Pause a deployment's rollout where it stands, as kubectl rollout pause does. Pods already running " \
                                 "keep running, and changes to its template wait until rollout_resume. A paused deployment cannot be " \
                                 "rolled back or restarted until it is resumed",
                    params_schema: { "type" => "object", "properties" => { "namespace" => NAMESPACE, "resource" => deployment }, "required" => [ "resource" ] },
                    read_only: false
          pack.tool RESUME,
                    summary: "Resumes a paused deployment's rollout.",
                    description: "Resume a paused deployment's rollout, as kubectl rollout resume does, so its pods roll out to its template",
                    params_schema: { "type" => "object", "properties" => { "namespace" => NAMESPACE, "resource" => deployment }, "required" => [ "resource" ] },
                    read_only: false
          pack.tool RUN_NOW,
                    summary: "Starts a cronjob's job right away, outside its schedule.",
                    description: "Start a cronjob's job now, outside its schedule, as kubectl create job --from=cronjob does. The job is " \
                                 "the cronjob's own template, marked as started by hand, and workload_runs follows it",
                    params_schema: { "type" => "object", "properties" => { "namespace" => NAMESPACE, "resource" => cronjob }, "required" => [ "resource" ] },
                    read_only: false
          pack.tool SUSPEND,
                    summary: "Stops a cronjob from starting new jobs.",
                    description: "Stop a cronjob from starting new jobs, by setting its suspend. Jobs already running carry on",
                    params_schema: { "type" => "object", "properties" => { "namespace" => NAMESPACE, "resource" => cronjob }, "required" => [ "resource" ] },
                    read_only: false
          pack.tool RESUME_SCHEDULE,
                    summary: "Lets a suspended cronjob start jobs on its schedule again.",
                    description: "Let a suspended cronjob start jobs on its schedule again. Without a starting deadline, the runs it " \
                                 "missed while suspended start at once",
                    params_schema: { "type" => "object", "properties" => { "namespace" => NAMESPACE, "resource" => cronjob }, "required" => [ "resource" ] },
                    read_only: false
        end

        def rollout_pause(environment_row:, arguments:) = set_paused(environment_row, arguments, true)

        def rollout_resume(environment_row:, arguments:) = set_paused(environment_row, arguments, false)

        def suspend_cronjob(environment_row:, arguments:) = set_suspended(environment_row, arguments, true)

        def resume_cronjob(environment_row:, arguments:) = set_suspended(environment_row, arguments, false)

        def run_cronjob_now(environment_row:, arguments:)
          workload = find_workload(environment_row, arguments.merge("resource" => kind_prefixed(arguments["resource"], CRONJOB)))
          fail! "#{label(workload)} is not a cronjob, so it has no job to start by hand." unless workload[:kind].key == CRONJOB

          name = manual_job_name(workload[:name])
          path = self.class.collection(WORKLOADS.fetch(JOB), workload[:namespace])
          begin
            api(environment_row).post(path, job_from(workload[:object], name))
          rescue KubernetesApi::Forbidden => error
            fail! Sentence.all(error, "The service account's role cannot start a job. Give it create on jobs in #{workload[:namespace]}, then run it again.")
          end
          answer("Started job/#{name} in #{workload[:namespace]} from #{label(workload)}, as kubectl create job --from does. " \
                 "#{Runs::WORKLOAD_RUNS} with run #{name} follows it.", "kubectl get job/#{name} -n #{workload[:namespace]}")
        end

        private

        def set_paused(environment_row, arguments, paused)
          workload = find_workload(environment_row, arguments.merge("resource" => kind_prefixed(arguments["resource"], DEPLOYMENT)))
          unless workload[:kind].key == DEPLOYMENT
            fail! "#{label(workload)} cannot be #{paused ? 'paused' : 'resumed'}. Only a deployment's rollout pauses."
          end
          command = "kubectl rollout status #{workload[:kind].key}/#{workload[:name]} -n #{workload[:namespace]}"
          if workload[:object].dig("spec", "paused").present? == paused
            return answer("#{label(workload)} is already #{paused ? 'paused' : 'not paused'}, so nothing changed.", command)
          end

          change!(environment_row, workload, { "spec" => { "paused" => paused } }, KubernetesApi::PATCH_MERGE)
          words = if paused
            "#{label(workload)} is paused. Its rollout stops where it is and pods already running keep running. Changes to its " \
              "template wait until rollout_resume, and it cannot be rolled back or restarted while paused."
          else
            "#{label(workload)} is resumed. Its pods roll out to its template as its strategy says. Read its status again in a minute to see them come up."
          end
          answer(words, command)
        end

        def set_suspended(environment_row, arguments, suspended)
          workload = find_workload(environment_row, arguments.merge("resource" => kind_prefixed(arguments["resource"], CRONJOB)))
          fail! "#{label(workload)} is not a cronjob, so it has no schedule to #{suspended ? 'suspend' : 'resume'}." unless workload[:kind].key == CRONJOB

          command = "kubectl get cronjob/#{workload[:name]} -n #{workload[:namespace]}"
          if workload[:object].dig("spec", "suspend").present? == suspended
            return answer("#{label(workload)} is already #{suspended ? 'suspended' : 'running on its schedule'}, so nothing changed.", command)
          end

          change!(environment_row, workload, { "spec" => { "suspend" => suspended } }, KubernetesApi::PATCH_MERGE)
          words = if suspended
            "#{label(workload)} is suspended. It starts no new jobs until resume_cronjob, and jobs already running carry on."
          else
            missed = workload[:object].dig("spec", "startingDeadlineSeconds") ? "Runs it missed start only within its starting deadline." : "Runs it missed while suspended start at once."
            "#{label(workload)} runs on its schedule (#{workload[:object].dig('spec', 'schedule')}) again. #{missed}"
          end
          answer(words, command)
        end

        # A name alone is read as the kind the tool acts on, so a deployment and a cronjob of one name are never confused.
        def kind_prefixed(reference, kind)
          given = reference.to_s.strip
          given.include?("/") || given.empty? ? given : "#{kind}/#{given}"
        end

        def manual_job_name(cronjob)
          suffix = "#{MANUAL_SUFFIX}#{SecureRandom.hex(SUFFIX_BYTES)}"
          "#{cronjob.first(NAME_MOST - suffix.length).delete_suffix('-')}#{suffix}"
        end

        def job_from(cronjob, name)
          template = cronjob.dig("spec", "jobTemplate").to_h
          {
            "apiVersion" => "batch/v1", "kind" => WORKLOADS.fetch(JOB).name,
            "metadata" => {
              "name" => name, "namespace" => cronjob.dig("metadata", "namespace"),
              "annotations" => { Runs::INSTANTIATE => Runs::MANUAL }.merge(template.dig("metadata", "annotations").to_h),
              "labels" => template.dig("metadata", "labels").presence,
              "ownerReferences" => [ { "apiVersion" => "batch/v1", "kind" => WORKLOADS.fetch(CRONJOB).name, "name" => cronjob.dig("metadata", "name"),
                                       "uid" => cronjob.dig("metadata", "uid"), "controller" => true } ]
            }.compact,
            "spec" => template["spec"].to_h
          }
        end
      end
    end
  end
end
