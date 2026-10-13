import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { whenClosed } from "@/lib/handlers"
import { testRunWorkflowPath } from "@/lib/routes"
import type { WorkflowDetail } from "@/types/serializers"
import { InputsFields, defaultValues } from "@/pages/halon/components/workflows/inputs-fields"

// A test of the draft as the person testing: reads happen for real, and each change only shows what it would do unless
// they turn it on here.
export function TestRunDialog({ workflow, open, onClose }: { workflow: WorkflowDetail; open: boolean; onClose: () => void }) {
  const [values, setValues] = useState(() => defaultValues(workflow.testInputs))
  const [real, setReal] = useState<string[]>([])
  const [processing, setProcessing] = useState(false)

  function change(key: string, value: string) {
    setValues((current) => ({ ...current, [key]: value }))
  }

  function toggle(stepId: string, checked: boolean) {
    setReal((current) => (checked ? [ ...current, stepId ] : current.filter((each) => each !== stepId)))
  }

  function finish() {
    setProcessing(false)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    setProcessing(true)
    router.post(testRunWorkflowPath(workflow.id), { inputs: values, real_step_ids: real }, { onSuccess: onClose, onFinish: finish })
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Test {workflow.name}</DialogTitle>
            <DialogDescription>
              It runs the {workflow.showsDraft ? "draft" : "live version"} as you, with what you may read. Every step that would change something only shows what it would do, unless you turn it on below.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-5 py-4">
            <InputsFields idPrefix="test-input" inputs={workflow.testInputs} values={values} onChange={change} />
            {workflow.changingSteps.length > 0 && (
              <div className="flex flex-col gap-2">
                <p className="text-sm font-medium">Make these changes for real</p>
                {workflow.changingSteps.map((step) => (
                  <div key={step.id} className="flex items-center gap-2">
                    <Checkbox id={`real-${step.id}`} checked={real.includes(step.id)} onCheckedChange={(checked) => toggle(step.id, checked === true)} />
                    <Label htmlFor={`real-${step.id}`} className="font-normal">{step.name}</Label>
                  </div>
                ))}
              </div>
            )}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>Start the test</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
