import { DeleteWorkflowCard } from "@/pages/halon/components/workflow/delete-workflow-card"
import { ReachCard } from "@/pages/halon/components/workflows/reach-card"
import { SettingsCard } from "@/pages/halon/components/workflows/settings-card"
import type { TeamChoice } from "@/pages/halon/components/workflows/types"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"
import type { WorkflowDetail } from "@/types/serializers"

// The workflow's own settings beside the canvas: what it can do as its own identity, and its name, owner, limits and
// how it meets a freeze, and deleting it.
export function SettingsView({ workflow, teams }: { workflow: WorkflowDetail; teams: TeamChoice[] }) {
  const access = useWorkflowAccess()

  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      <div className="mx-auto grid w-full max-w-3xl gap-6 px-4 py-6">
        <ReachCard workflow={workflow} />
        <SettingsCard key={workflow.id} workflow={workflow} teams={teams} canManage={access.manage} />
        {access.manage && <DeleteWorkflowCard workflow={workflow} />}
      </div>
    </div>
  )
}
