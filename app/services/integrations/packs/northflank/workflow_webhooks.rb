module Integrations
  module Packs
    class Northflank < NativePack
      # A workflow's webhook trigger, whose address starts a run for whoever requests it, so Northflank's documentation says
      # to treat it as a credential (Run a workflow using a webhook). A trigger is { kind: webhook, ref, spec: { token } }
      # in the workflow's triggers, its address https://webhooks.northflank.com/workflows/<token>, and a workflow is updated
      # by sending its whole definition back (Update workflow). Firefight makes the token itself, so it never passes
      # through Halon, and the person reveals the address in Firefight or hands it to another tool by its reference
      # (Integrations::SecretHandoffs). Every answer and every body Halon sends keeps tokens out of sight. A read shows
      # [hidden], and a change that sends a trigger back as [hidden] has its token put back from Northflank first.
      module WorkflowWebhooks
        ADD_WEBHOOK = "add_workflow_webhook".freeze
        WEBHOOK_KIND = "webhook".freeze
        WEBHOOK_ADDRESS = "https://webhooks.northflank.com/workflows/%<token>s".freeze
        GIT_KINDS = %w[vcs-push vcs-pr vcs-release vcs-pr-label vcs-check-suite].freeze
        # What Northflank's update takes, which the definition it answers with holds besides read-only fields such as its
        # status (UpdateWorkflowData in @northflank/js-client).
        WRITABLE = %w[name description apiVersion spec arguments gitops $schema richInputs options teardownSpec argumentOverrides
                      crossProjectAccess stageId triggers].freeze
        # A trigger's ref is read in the workflow as ${triggers.<ref>...}, so it keeps to the letters, digits and hyphens
        # Northflank's own ids use.
        REF = /\A[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*\z/
        REF_LIMIT = 100
        HIDDEN = "[hidden]".freeze
        # Paths whose body carries triggers, which are a workflow, a release flow and a preview blueprint.
        WITH_TRIGGERS = %r{\A(workflows/[^/]+|pipelines/[^/]+/release-flows/[^/]+|preview-blueprints/[^/]+)\z}
        TOKEN_LENGTH = 48

        def self.included(pack)
          pack.tool ADD_WEBHOOK,
                    description: "Add a webhook trigger to a Northflank workflow, so a request to its address starts a run, such as from a " \
                                 "CI job after a release. Firefight makes the address, which works as a password, so it is never shown to " \
                                 "you: the person reveals it under this step, and value_from on a tool that stores secrets takes the " \
                                 "reference this answers with to store it there unseen",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "workflow" => { "type" => "string", "description" => "The workflow's id, as api_request GET workflows lists it" },
                        "ref" => { "type" => "string", "description" => "The trigger's name, letters, digits and hyphens, such as release-webhook. " \
                                                                        "The workflow reads its values as ${triggers.<ref>...}" }
                      },
                      "required" => %w[workflow ref]
                    },
                    read_only: false
        end

        def add_workflow_webhook(environment_row:, arguments:)
          workflow_id = arguments["workflow"].to_s.strip
          fail!("workflow must be the workflow's id, such as deploy-production.") unless workflow_id.match?(REF)
          ref = arguments["ref"].to_s.strip
          fail!("ref must be letters, digits and hyphens, at most #{REF_LIMIT}, such as release-webhook.") unless ref.match?(REF) && ref.length <= REF_LIMIT

          project = project_of(environment_row)
          definition = workflow_of(environment_row, project, workflow_id)
          triggers = Array(definition["triggers"])
          fail!("Workflow #{workflow_id} already has a trigger called #{ref}. Choose another ref.") if triggers.any? { |trigger| trigger["ref"] == ref }

          added = { "kind" => WEBHOOK_KIND, "ref" => ref, "spec" => { "token" => SecureRandom.alphanumeric(TOKEN_LENGTH) } }
          changing_workflow { api(environment_row).update_workflow(project, workflow_id, definition.slice(*WRITABLE).merge("triggers" => triggers + [ added ])) }

          reference = SecretHandoffs.reference_for(environment_row, ADD_WEBHOOK, [ project, workflow_id, ref ].join("/"))
          SecretHandoffs.reveal_result(webhook_said(definition, workflow_id, ref, reference), reference: reference,
                                                                                              title: "Webhook address of #{definition['name'] || workflow_id}, trigger #{ref}",
                                                                                              link: project_link(environment_row))
        end

        # The address a reference names, read from Northflank now, from a project this connection reaches.
        def secret_value(environment_row:, path:)
          project, workflow_id, ref = path.to_s.split("/", 3)
          fail!("That reference names no workflow webhook.") unless [ project, workflow_id, ref ].all?(&:present?)
          fail!("This connection no longer reaches project #{project}.") unless ConnectionSettings.of(environment_row).scopes.include?(project)

          trigger = Array(workflow_of(environment_row, project, workflow_id)["triggers"]).find { |each| each["kind"] == WEBHOOK_KIND && each["ref"] == ref }
          token = trigger&.dig("spec", "token")
          token.present? ? format(WEBHOOK_ADDRESS, token: token) : nil
        end

        private

        def workflow_of(environment_row, project, workflow_id)
          api(environment_row).workflow(project, workflow_id)
        rescue NorthflankApi::NotFound
          fail!("Northflank has no workflow #{workflow_id} in project #{project}.")
        end

        def changing_workflow
          yield
        rescue NorthflankApi::Error => error
          raise unless error.message.start_with?("Northflank answered 403")

          fail!(Sentence.all(error, "The API token's role cannot change workflows. In Northflank, give the role Project, Workflows, " \
                                   "General, Update, then run it again."))
        end

        def webhook_said(definition, workflow_id, ref, reference)
          git_refs = Array(definition["triggers"]).select { |trigger| GIT_KINDS.include?(trigger["kind"]) }.filter_map { |trigger| trigger["ref"].presence }
          [
            "Added webhook trigger #{ref} to workflow #{definition['name'] || workflow_id}.",
            "Its address works as a password, so it is not shown to you. The person reveals and copies it from the card under this step in Firefight.",
            "To store it in another system without it being shown, such as a GitHub Actions secret, pass value_from #{reference}.",
            "A GET or POST to the address starts a run. Query parameters set what the run uses: <git trigger ref>.branch, .sha, " \
            ".pullRequestId and .repoUrl set a Git trigger's values, name and description label the run, and any other parameter " \
            "becomes an argument, read as ${args.<name>}. Northflank ignores arguments in a POST body.",
            (git_refs.any? ? "This workflow's Git triggers are #{git_refs.to_sentence}, so a commit is passed as #{git_refs.first}.sha." : "This workflow has no Git trigger, so a branch or commit can only be passed as an argument.")
          ].join(" ")
        end

        # A body that sends a trigger back as Halon read it gets its token from Northflank, and a token Halon wrote itself
        # is refused, since it would have passed through the model.
        def webhook_tokens_restored(environment_row, path, body)
          return body unless body.is_a?(Hash) && path.match?(WITH_TRIGGERS)

          triggers = Array(body["triggers"])
          webhooks = triggers.select { |trigger| trigger.is_a?(Hash) && trigger["kind"] == WEBHOOK_KIND }
          return body if webhooks.empty?

          if webhooks.any? { |trigger| trigger.dig("spec", "token").to_s != HIDDEN }
            fail_policy!("A webhook trigger's token works as a password, so Firefight makes it, never you. Add one to a workflow with " \
                         "#{ADD_WEBHOOK}, and send an existing one back with its token as #{HIDDEN}, as you read it.")
          end

          live = Array(api(environment_row).request("GET", project_of(environment_row), path).dig("data", "triggers"))
          body.merge("triggers" => triggers.map { |trigger| webhooks.include?(trigger) ? with_live_token(trigger, live) : trigger })
        end

        def with_live_token(trigger, live)
          found = live.find { |each| each["kind"] == WEBHOOK_KIND && ((trigger["id"].present? && each["id"] == trigger["id"]) || each["ref"] == trigger["ref"]) }
          fail!("Northflank has no webhook trigger #{trigger['ref'] || trigger['id']} here to keep, so its token cannot be sent back.") unless found

          trigger.merge("spec" => trigger["spec"].to_h.merge("token" => found.dig("spec", "token")))
        end
      end
    end
  end
end
