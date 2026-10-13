import { router } from "@inertiajs/react"
import { IconPin } from "@tabler/icons-react"
import { type ChangeEvent, useState } from "react"

import { SearchableSelect } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { formatDateTime } from "@/lib/formatters"
import { WORKFLOW_STEP_EFFECT } from "@/lib/generated/constants"
import { isObject, jsonObject, type JsonObject } from "@/lib/tool-fields"
import { workflowTestRunsPath } from "@/lib/routes"
import type { WorkflowDocument, WorkflowRunRow } from "@/types/serializers"

interface TestRunDialogProps {
  open: boolean
  workflowId: string
  document: WorkflowDocument
  runs: WorkflowRunRow[]
  // A step tried with only the steps before it, or null to try the whole workflow.
  upTo: { id: string; title: string } | null
  onOpenChange: (open: boolean) => void
}

const NOTHING = "nothing"

function payloadText(value: Record<string, unknown>): string {
  return Object.keys(value).length === 0 ? "" : JSON.stringify(value, null, 2)
}

// Trying the draft: sample answers to the trigger's inputs, a sample of what started it, written or taken from an earlier
// run, and which changes run for real. Every other change is only pretended, and a pinned step's output stands in for it.
export function TestRunDialog({ open, workflowId, document, runs, upTo, onOpenChange }: TestRunDialogProps) {
  const [ inputs, setInputs ] = useState<Record<string, string>>(() => Object.fromEntries(document.trigger.inputs.map((input) => [ input.key, input.default ?? "" ])))
  const [ payload, setPayload ] = useState("")
  const [ source, setSource ] = useState<string>(NOTHING)
  const [ real, setReal ] = useState<string[]>([])
  const changes = document.steps.filter((step) => step.effect === WORKFLOW_STEP_EFFECT.CHANGES)
  const pinned = document.steps.filter((step) => step.pin)
  const sources = runs.filter((run) => Object.keys(run.triggerPayload).length > 0)
  const parsed = parsePayload(payload)

  function typedInput(key: string) {
    return (event: ChangeEvent<HTMLInputElement>) => setInputs({ ...inputs, [key]: event.target.value })
  }

  function typedPayload(event: ChangeEvent<HTMLTextAreaElement>) {
    setPayload(event.target.value)
    setSource(NOTHING)
  }

  function chooseSource(value: string | null) {
    const chosen = sources.find((run) => run.id === value)
    setSource(value ?? NOTHING)
    setPayload(chosen ? payloadText(chosen.triggerPayload) : "")
  }

  function turned(stepId: string) {
    return (checked: boolean) => setReal(checked ? [ ...real, stepId ] : real.filter((each) => each !== stepId))
  }

  function start() {
    if (parsed === null) {
      return
    }
    router.post(workflowTestRunsPath(workflowId), { inputs, trigger_payload: parsed, up_to: upTo?.id ?? null, real_step_keys: real }, { onSuccess: () => onOpenChange(false) })
  }

  const options = [ { value: NOTHING, label: "Write it here" }, ...sources.map((run) => ({ value: run.id, label: `The run of ${formatDateTime(run.createdAt)}` })) ]

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{upTo ? `Try ${upTo.title}` : "Try the workflow"}</DialogTitle>
          <DialogDescription>
            {upTo
              ? "It runs with only the steps before it. A step before it that ran before, or has a pinned output, is not called again."
              : "It runs the draft as it is now. Every change is only pretended unless you turn it on below."}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-5">
          {document.trigger.inputs.length > 0 && (
            <section className="space-y-2">
              <h4 className="font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">Inputs</h4>
              {document.trigger.inputs.map((input) => (
                <div key={input.key} className="space-y-1">
                  <Label htmlFor={`test-input-${input.key}`} className="text-xs">{input.question}</Label>
                  <Input id={`test-input-${input.key}`} value={inputs[input.key] ?? ""} onChange={typedInput(input.key)} placeholder={input.key} />
                </div>
              ))}
            </section>
          )}
          <section className="space-y-2">
            <h4 className="font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">What started it</h4>
            {sources.length > 0 && (
              <SearchableSelect value={source} onValueChange={chooseSource} options={options} searchPlaceholder="Search runs" emptyText="No run by that date" />
            )}
            <Label htmlFor="test-trigger-payload" className="sr-only">What started the run, as JSON</Label>
            <Textarea
              id="test-trigger-payload"
              value={payload}
              onChange={typedPayload}
              rows={5}
              placeholder={'{ "service": "web" }'}
              className="font-mono text-xs"
              aria-invalid={parsed === null}
            />
            {parsed === null ? (
              <p className="text-xs text-destructive">Write it as JSON named values, such as {'{ "service": "web" }'}.</p>
            ) : (
              <p className="text-xs text-fg-muted">Steps read it as {"{{trigger.service}}"}. Leave it empty when nothing in the workflow reads it.</p>
            )}
          </section>
          {changes.length > 0 && (
            <section className="space-y-2">
              <h4 className="font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">Changes</h4>
              {changes.map((step) => (
                <div key={step.id} className="flex items-center justify-between gap-3">
                  <Label htmlFor={`test-real-${step.id}`} className="text-xs">{step.title} for real</Label>
                  <Switch id={`test-real-${step.id}`} checked={real.includes(step.id)} onCheckedChange={turned(step.id)} />
                </div>
              ))}
            </section>
          )}
          {pinned.length > 0 && (
            <section className="space-y-1.5">
              <h4 className="font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">Pinned</h4>
              {pinned.map((step) => (
                <p key={step.id} className="flex items-center gap-1.5 text-xs text-fg-secondary">
                  <IconPin className="size-3.5 text-brand" />
                  {step.title} uses its pinned output and is not called.
                </p>
              ))}
            </section>
          )}
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button type="button" disabled={parsed === null} onClick={start}>Start test run</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// What was written, as named values, an empty object for nothing, or null when it is not JSON named values.
function parsePayload(text: string): JsonObject | null {
  if (text.trim().length === 0) {
    return {}
  }
  try {
    const value: unknown = JSON.parse(text)
    return isObject(value) ? jsonObject(value) : null
  } catch {
    return null
  }
}
