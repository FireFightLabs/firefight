# Which of the workspace's workflows run a skill, which decides whether it can be deleted or renamed. A workflow uses a
# skill when its live version or its open draft has a step whose config names it (skill), at any depth, so a step
# inside a for each counts too.
module Chat::CustomSkill::Usage
  extend ActiveSupport::Concern

  USING = "jsonb_path_exists(workflow_versions.steps, '$.**.skill ? (@ == $name)', jsonb_build_object('name', %s::text))".freeze

  class_methods do
    def with_usage_counts
      select("#{table_name}.*", "(#{using_query(workspace: "#{table_name}.workspace_id", name: "#{table_name}.name")}) AS usage_count")
    end

    def using_query(workspace:, name:)
      "SELECT COUNT(DISTINCT workflow_versions.workflow_id) FROM workflow_versions " \
        "JOIN workflows ON workflows.id = workflow_versions.workflow_id " \
        "WHERE workflows.workspace_id = #{workspace} " \
        "AND workflow_versions.status IN ('#{Workflow::Version::STATUS_LIVE}', '#{Workflow::Version::STATUS_DRAFT}') " \
        "AND #{format(USING, name)}"
    end
  end

  # The workflows that run it, by name.
  def workflows_using
    Workflow.where(workspace_id: workspace_id)
            .where(id: Workflow::Version.where(status: [ Workflow::Version::STATUS_LIVE, Workflow::Version::STATUS_DRAFT ])
                                        .where(format(USING, ":skill_name"), skill_name: name).select(:workflow_id))
            .ordered
  end

  def usage_count = has_attribute?(:usage_count) ? self[:usage_count].to_i : workflows_using.count

  # A copy's workflows carry on with Firefight's own skill of the same name, so only a skill of the workspace's own is
  # held back while a workflow runs it.
  def deletion_blocked_reason
    return if copy? || usage_count.zero?

    "#{usage_count} #{'workflow'.pluralize(usage_count)} #{usage_count == 1 ? 'runs' : 'run'} #{name}, so take it out of " \
      "#{usage_count == 1 ? 'that workflow' : 'those workflows'} before deleting it."
  end

  # A workflow names a skill by its name, so a skill a workflow runs keeps it.
  def rename_blocked_reason
    return if usage_count.zero?

    "#{usage_count} #{'workflow'.pluralize(usage_count)} #{usage_count == 1 ? 'runs' : 'run'} #{name} by its name, so it keeps it."
  end
end
