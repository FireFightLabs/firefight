import { router } from "@inertiajs/react"
import { IconPin, IconPinnedOff } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import { workflowPinPath } from "@/lib/routes"
import { JsonBlock } from "@/pages/halon/components/workflow/json-block"
import { PinDialog } from "@/pages/halon/components/workflow/pin-dialog"
import { CANVAS_VISIT } from "@/pages/halon/hooks/use-workflow-edits"
import { routeWords } from "@/pages/halon/lib/workflow/labels"
import type { WorkflowStepNode } from "@/types/serializers"

// A step's pinned output in its settings: what test runs use in its place, with Edit and Unpin, or Pin an output to
// write one.
export function PinnedOutput({ workflowId, step, editable }: { workflowId: string; step: WorkflowStepNode; editable: boolean }) {
  const [ editing, setEditing ] = useState(false)

  function edit() {
    setEditing(true)
  }

  function unpin() {
    router.delete(workflowPinPath(workflowId, step.id), CANVAS_VISIT)
  }

  return (
    <section className="space-y-2">
      <h4 className="font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">Pinned output</h4>
      {step.pin ? (
        <>
          <JsonBlock label={step.pin.route ? `Takes ${routeWords(step.pin.route)} and gives` : "Gives"} value={step.pin.output} />
          <p className="text-xs text-fg-muted">Test runs use it in the step&apos;s place. Published runs always run the step.</p>
          {editable && (
            <div className="flex gap-2">
              <Button type="button" variant="outline" size="sm" className="h-7 text-xs" onClick={edit}>
                <IconPin className="size-3.5" />
                Edit
              </Button>
              <Button type="button" variant="outline" size="sm" className="h-7 text-xs" onClick={unpin}>
                <IconPinnedOff className="size-3.5" />
                Unpin
              </Button>
            </div>
          )}
        </>
      ) : (
        <>
          <p className="text-xs text-fg-muted">Pin what it gives, from a run or written here, and test runs try the steps after it without calling it.</p>
          {editable && (
            <Button type="button" variant="outline" size="sm" className="h-7 text-xs" onClick={edit}>
              <IconPin className="size-3.5" />
              Pin an output
            </Button>
          )}
        </>
      )}
      {editing && <PinDialog open={editing} workflowId={workflowId} step={step} onOpenChange={setEditing} />}
    </section>
  )
}
