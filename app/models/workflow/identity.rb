# Who a workflow's runs act as: an agent made with the workflow and named after it, holding only the grants an admin
# gave it, never the reach of whoever built or started it. What it needs is read from the steps of a version
# (Workflow::Version#reach), so publishing says exactly what the workflow will be able to do and grants it in one step.
module Workflow::Identity
  extend ActiveSupport::Concern

  AGENT_SLUG_PREFIX = "workflow_".freeze

  included do
    after_update_commit :keep_agent_named, if: -> { saved_change_to_name? && agent }
  end

  # One thing it needs and whether its identity holds it now.
  Standing = Data.define(:needed, :held)

  def agent_name = "#{name} workflow"

  # Made once, the first time it is asked for, in one statement a second caller cannot also win. Its own savepoint, so
  # losing takes the agent it made back out even inside a caller's transaction.
  def ensure_agent!
    return agent if agent

    transaction(requires_new: true) do
      made = workspace.agents.create!(name: agent_name, slug: free_agent_slug, description: "Runs the #{name} workflow. It holds only what an admin granted it.")
      claimed = self.class.where(id: id, agent_id: nil).update_all(agent_id: made.id, updated_at: Time.current) == 1
      raise ActiveRecord::Rollback unless claimed

      signal_workflow_page
    end
    reload.agent
  end

  # Each thing a version needs, with whether the identity holds it now.
  def standing(version = live_version || draft)
    return [] unless version

    resolved = agent && Ability::Resolver.resolve(agent, workspace)
    version.reach.map { |needed| Standing.new(needed: needed, held: resolved.present? && needed.held_by?(agent, workspace, resolved)) }
  end

  def missing_reach(version = live_version || draft) = standing(version).reject(&:held).map(&:needed)

  # Grants the identity what the version needs and does not hold yet, in every environment, as by.
  def grant_reach!(version, by:)
    ensure_agent!
    missing_reach(version).each do |needed|
      Ability::Grant.grant!(workspace: workspace, principal: agent, target: needed.target, granted_by: by)
    end
  end

  private

  def free_agent_slug
    base = "#{AGENT_SLUG_PREFIX}#{slug}".first(60)
    taken = workspace.agents.where("slug = ? OR slug LIKE ?", base, "#{base}_%").pluck(:slug).to_set
    return base unless taken.include?(base)

    (2..).lazy.map { |number| "#{base}_#{number}" }.find { |candidate| !taken.include?(candidate) }
  end

  def keep_agent_named = agent.update!(name: agent_name)
end
