import { router } from "@inertiajs/react"
import { type ChangeEvent, useState } from "react"

import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { isObject, jsonObject, type JsonObject } from "@/lib/tool-fields"
import { workflowPinsPath } from "@/lib/routes"
import { CANVAS_VISIT } from "@/pages/halon/hooks/use-workflow-edits"
import { routeLabel } from "@/pages/halon/lib/workflow/labels"
import type { WorkflowStepNode } from "@/types/serializers"

const NO_ROUTE = "none"

interface PinDialogProps {
  open: boolean
  workflowId: string
  step: WorkflowStepNode
  onOpenChange: (open: boolean) => void
}

// Writing the output a test run uses in a step's place, by hand or by changing the one pinned, with the route it takes
// for a step that has routes.
export function PinDialog({ open, workflowId, step, onOpenChange }: PinDialogProps) {
  const [ text, setText ] = useState(() => JSON.stringify(step.pin?.output ?? {}, null, 2))
  const [ route, setRoute ] = useState(step.pin?.route ?? step.routes[0] ?? NO_ROUTE)
  const parsed = parse(text)

  function typed(event: ChangeEvent<HTMLTextAreaElement>) {
    setText(event.target.value)
  }

  function save() {
    if (!parsed) {
      return
    }
    const payload = { step_id: step.id, output: parsed, route: route === NO_ROUTE ? null : route }
    router.post(workflowPinsPath(workflowId), payload, { ...CANVAS_VISIT, onSuccess: () => onOpenChange(false) })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Pin {step.title}&apos;s output</DialogTitle>
          <DialogDescription>Test runs use it in the step&apos;s place, so the steps after it are tried without calling it.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1">
            <Label htmlFor={`pin-${step.id}`} className="text-xs">What it gives, as JSON</Label>
            <Textarea id={`pin-${step.id}`} value={text} onChange={typed} rows={8} className="font-mono text-xs" aria-invalid={parsed === null} />
            {parsed === null && <p className="text-xs text-destructive">Write it as JSON named values, such as {'{ "count": 3 }'}.</p>}
          </div>
          {step.routes.length > 0 && (
            <div className="space-y-1">
              <Label htmlFor={`pin-route-${step.id}`} className="text-xs">Route it takes</Label>
              <Select value={route} onValueChange={setRoute}>
                <SelectTrigger id={`pin-route-${step.id}`} className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={NO_ROUTE}>None</SelectItem>
                  {step.routes.map((each) => <SelectItem key={each} value={each}>{routeLabel(each, step.routeLabels)}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          )}
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button type="button" disabled={parsed === null} onClick={save}>Pin output</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function parse(text: string): JsonObject | null {
  try {
    const value: unknown = JSON.parse(text)
    return isObject(value) ? jsonObject(value) : null
  } catch {
    return null
  }
}
