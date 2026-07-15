# The shared identity contract for anything a request is authorized AS:
# humans (WorkspaceMembership), tokens (ApiKey), and later Agents. The
# Ability Gateway's grants attach to principals; until then this pins the
# interface every principal must answer.
module Principal
  extend ActiveSupport::Concern

  def principal_label
    "#{actor_kind}:#{actor_display_name}"
  end
end
