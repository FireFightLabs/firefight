import { router } from "@inertiajs/react"
import { IconPlayerPlay } from "@tabler/icons-react"
import { useState } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { disableWorkflowPath, enableWorkflowPath } from "@/lib/routes"
import { RunDialog, type RunTarget } from "@/pages/halon/components/workflows/run-dialog"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"
import type { WorkflowDetail } from "@/types/serializers"

// What is done with the workflow as a whole, beside its version's actions: run the live version by hand, and switch it on
// or off. Deleting it is in its settings.
export function WorkflowControls({ workflow }: { workflow: WorkflowDetail }) {
  const access = useWorkflowAccess()
  const [ running, setRunning ] = useState(false)
  const target: RunTarget | null = running ? { id: workflow.id, name: workflow.name, inputs: workflow.inputs } : null

  function close() {
    setRunning(false)
  }

  function openRun() {
    setRunning(true)
  }

  function toggleEnabled(checked: boolean) {
    router.patch(checked ? enableWorkflowPath(workflow.id) : disableWorkflowPath(workflow.id), {}, { preserveScroll: true, preserveState: true })
  }

  return (
    <>
      {access.build && (
        <Blocked reason={workflow.runBlockedReason ?? undefined} side="bottom">
          <Button type="button" size="sm" variant="outline" disabled={Boolean(workflow.runBlockedReason)} onClick={openRun}>
            <IconPlayerPlay className="size-4" />
            Run
          </Button>
        </Blocked>
      )}
      {access.manage && workflow.liveNumber && (
        <label className="flex items-center gap-2 text-xs text-fg-secondary">
          <Switch checked={workflow.enabled} onCheckedChange={toggleEnabled} aria-label={workflow.enabled ? "Turn off" : "Turn on"} />
          {workflow.enabled ? "On" : "Off"}
        </label>
      )}
      <RunDialog target={target} onClose={close} />
    </>
  )
}
