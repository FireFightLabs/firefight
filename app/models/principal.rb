# The shared identity contract for anything a request is authorized AS:
# humans (WorkspaceMembership), tokens (ApiKey), and Agents. The
# Ability Gateway's grants attach to principals. Until then this pins the
# interface every principal must answer.
module Principal
  extend ActiveSupport::Concern

  included do
    has_many :ability_grants, class_name: "Ability::Grant", as: :principal, dependent: :destroy
  end

  # Authority held before any grant, as a stable key the permissions UI
  # explains and `implicitly_allowed?` enforces. Keep the two in step.
  def implicit_authority
    :none
  end

  def principal_label
    "#{actor_kind}:#{actor_display_name}"
  end

  # Whether this principal may read the given MCP resource. Humans read
  # everything in their workspace, and so does anything resolving to a human,
  # such as a personal token or an OAuth grant. Credential principals override.
  def mcp_readable?(_resource)
    true
  end

  # Authority a principal holds without an explicit grant. None by default, so
  # credential principals (ApiKey, Agent) act only on granted abilities.
  # Humans override with member-level reads.
  def implicitly_allowed?(_action)
    false
  end
end
