import { type ChangeEvent, type FocusEvent, type KeyboardEvent, useState } from "react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { WORKFLOW_EDIT_OPERATIONS, WORKFLOW_STEP_GROUP } from "@/lib/generated/constants"
import { FailureSettings } from "@/pages/halon/components/workflow/failure-settings"
import { StepBadges } from "@/pages/halon/components/workflow/step-badges"
import { StepConfigEditor } from "@/pages/halon/components/workflow/step-config-editor"
import { StepIcon } from "@/pages/halon/components/workflow/step-icon"
import { SuggestionCard } from "@/pages/halon/components/workflow/suggestion-card"
import { useStepDraft } from "@/pages/halon/hooks/use-step-draft"
import type { SendEdit } from "@/pages/halon/hooks/use-workflow-edits"
import { referencesFor } from "@/pages/halon/lib/workflow/references"
import type { CanvasStep, OtherWorkflow } from "@/pages/halon/lib/workflow/types"
import type { WorkflowDocument, WorkflowStepKind, WorkflowToolChoice } from "@/types/serializers"

const STEP_NAME = /^[a-z][a-z0-9_]{0,63}$/

interface StepSettingsProps {
  item: CanvasStep
  document: WorkflowDocument
  revision: number | null
  stepKinds: WorkflowStepKind[]
  tools: WorkflowToolChoice[] | undefined
  workflows: OtherWorkflow[]
  timeZones: string[]
  editable: boolean
  send: SendEdit
  onRemove: () => void
}

// A step's settings, docked beside the canvas: its name, what it does, what it hands on, what happens when it fails, and
// Halon's suggestions for it with the old value struck beside the new. Changes are applied together, naming the draft
// revision they were made on, so a change someone made since to the same step is refused with who made it.
export function StepSettings({ item, document, revision, stepKinds, tools, workflows, timeZones, editable, send, onRemove }: StepSettingsProps) {
  const { step, suggestion, pending } = item
  const kind = stepKinds.find((each) => each.key === step.kind) ?? null
  const draft = useStepDraft(step, revision)
  const [ name, setName ] = useState(step.name)
  const [ nameFor, setNameFor ] = useState(step.name)
  const references = referencesFor(step.id, document)
  const disabled = !editable || suggestion !== null

  if (nameFor !== step.name) {
    setNameFor(step.name)
    setName(step.name)
  }

  const nameError = STEP_NAME.test(name) ? null : "Lowercase letters, numbers and underscores, starting with a letter, such as check_logs."

  function typedName(event: ChangeEvent<HTMLInputElement>) {
    setName(event.target.value)
  }

  function saveName() {
    if (name === step.name || nameError) {
      return
    }
    send(WORKFLOW_EDIT_OPERATIONS.RENAME, { step_id: step.id, name }, { baseRevision: draft.baseRevision })
  }

  function nameBlurred(_event: FocusEvent<HTMLInputElement>) {
    saveName()
  }

  function nameKeyed(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "Enter") {
      event.preventDefault()
      saveName()
    }
  }

  function apply() {
    send(WORKFLOW_EDIT_OPERATIONS.CHANGE_CONFIG, { step_id: step.id, changes: draft.changes }, { baseRevision: draft.baseRevision, onSuccess: draft.reset })
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      <header className="flex items-start gap-2.5 border-b border-border p-3">
        <StepIcon icon={step.icon} halon={step.group === WORKFLOW_STEP_GROUP.HALON} />
        <div className="min-w-0 flex-1 space-y-1.5">
          <h3 className="truncate text-sm leading-tight font-semibold text-fg-headline">{step.title}</h3>
          <p className="text-xs text-fg-muted">{suggestion ? `Suggested by Halon · ${step.kindLabel}` : step.kindLabel}</p>
          <StepBadges item={item} />
        </div>
      </header>
      <div className="min-h-0 flex-1 space-y-5 overflow-y-auto p-3">
        {suggestion && <SuggestionCard suggestion={suggestion} />}
        {pending.map((each) => <SuggestionCard key={each.id} suggestion={each} />)}
        {step.grantNeeded && <p className="rounded-md border border-error-border bg-error-tint px-2.5 py-2 text-xs text-error">{step.grantNeeded}</p>}
        <div className="space-y-1">
          <Label htmlFor={`step-${step.id}-name`} className="text-xs">Name</Label>
          <Input id={`step-${step.id}-name`} value={name} onChange={typedName} onBlur={nameBlurred} onKeyDown={nameKeyed} disabled={disabled}
                 aria-invalid={nameError !== null} className="font-mono text-xs" />
          {nameError ? (
            <p className="text-xs text-destructive">{nameError}</p>
          ) : (
            <p className="text-xs text-fg-muted">Later steps read what it hands on as {`{{steps.${name}}}`}.</p>
          )}
        </div>
        {kind && <p className="text-xs leading-relaxed text-fg-secondary">{kind.description}</p>}
        <StepConfigEditor
          key={draft.generation}
          step={step}
          config={draft.draft.config}
          kind={kind}
          tools={tools}
          workflows={workflows}
          timeZones={timeZones}
          references={references}
          disabled={disabled}
          onChange={draft.changeConfig}
        />
        {step.outputs.length > 0 && (
          <section className="space-y-1.5">
            <h4 className="font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">Hands on</h4>
            <div className="flex flex-wrap gap-1">
              {step.outputs.map((field) => (
                <code key={field} className="rounded-sm border border-border bg-surface-code px-1.5 py-0.5 font-mono text-[11px] text-brand">{`steps.${step.name}.${field}`}</code>
              ))}
            </div>
          </section>
        )}
        <FailureSettings idPrefix={`step-${step.id}`} failure={draft.draft.failure} errors={draft.errors} disabled={disabled} onChange={draft.changeFailure} />
      </div>
      {editable && !suggestion && (
        <footer className="flex items-center justify-between gap-2 border-t border-border p-3">
          <Button type="button" variant="outline" size="sm" className="text-destructive" onClick={onRemove}>Remove step</Button>
          <div className="flex gap-2">
            {draft.dirty && <Button type="button" variant="ghost" size="sm" onClick={draft.reset}>Discard changes</Button>}
            <Button type="button" size="sm" disabled={!draft.dirty || draft.blocked !== null} onClick={apply}>Apply changes</Button>
          </div>
        </footer>
      )}
    </div>
  )
}
