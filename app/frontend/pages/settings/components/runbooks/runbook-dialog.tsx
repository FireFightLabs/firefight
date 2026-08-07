import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import type { Errors } from "@inertiajs/core"

import type {
  IncidentSeveritySettings,
  IncidentTypeSettings,
  RunbookCustomField,
  RunbookSettings,
} from "@/types/serializers"
import { runbookPath, runbooksPath } from "@/lib/routes"
import {
  CONDITION_FIELD_CUSTOM_FIELD,
  CONDITION_FIELD_INCIDENT_TYPE,
  CONDITION_FIELD_SEVERITY,
  OPERATOR_ONE_OF,
} from "@/pages/settings/lib/runbook-conditions"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { RunbookContentEditor } from "@/pages/settings/components/runbooks/runbook-content-editor"
import {
  RunbookStepsEditor,
  type EditableStep,
} from "@/pages/settings/components/runbooks/runbook-steps-editor"
import {
  RunbookConditionsEditor,
  type ConditionSectionState,
  type CustomFieldConditionState,
} from "@/pages/settings/components/runbooks/runbook-conditions-editor"

interface RunbookDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  runbook?: RunbookSettings | null
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
  customFields: RunbookCustomField[]
}

interface EditModel {
  name: string
  summary: string
  content: string
  externalUrl: string
  steps: EditableStep[]
  typeState: ConditionSectionState
  severityState: ConditionSectionState
  customFieldStates: CustomFieldConditionState[]
  alwaysAttach: boolean
}

function sectionState(runbook: RunbookSettings | null | undefined, field: string): ConditionSectionState {
  const condition = runbook?.conditions?.find((candidate) => candidate.conditionField === field)
  return {
    operator: condition?.operator ?? OPERATOR_ONE_OF,
    selectedIds: condition?.values ?? [],
  }
}

function customFieldStates(runbook: RunbookSettings | null | undefined): CustomFieldConditionState[] {
  return (runbook?.conditions ?? [])
    .filter((condition) => condition.conditionField === CONDITION_FIELD_CUSTOM_FIELD && condition.incidentFieldDefinitionId)
    .map((condition) => ({
      key: crypto.randomUUID(),
      fieldDefinitionId: condition.incidentFieldDefinitionId as string,
      operator: condition.operator,
      selectedIds: condition.values,
    }))
}

function initModel(runbook: RunbookSettings | null | undefined): EditModel {
  return {
    name: runbook?.name ?? "",
    summary: runbook?.summary ?? "",
    content: runbook?.content ?? "",
    externalUrl: runbook?.externalUrl ?? "",
    steps: (runbook?.steps ?? []).map((step) => ({
      key: crypto.randomUUID(),
      title: step.title,
      instruction: step.instruction ?? "",
    })),
    typeState: sectionState(runbook, CONDITION_FIELD_INCIDENT_TYPE),
    severityState: sectionState(runbook, CONDITION_FIELD_SEVERITY),
    customFieldStates: customFieldStates(runbook),
    alwaysAttach: runbook?.alwaysAttach ?? false,
  }
}

export function RunbookDialog({ open, onOpenChange, runbook, incidentTypes, severities, customFields }: RunbookDialogProps) {
  const isEdit = Boolean(runbook)
  const [model, setModel] = useState<EditModel>(() => initModel(runbook))
  const [errors, setErrors] = useState<Errors>({})
  const [processing, setProcessing] = useState(false)
  const [wasOpen, setWasOpen] = useState(open)

  if (open !== wasOpen) {
    setWasOpen(open)
    if (open) {
      setModel(initModel(runbook))
      setErrors({})
    }
  }

  function patch(next: Partial<EditModel>) {
    setModel((prev) => ({ ...prev, ...next }))
  }

  function setAlwaysAttach(alwaysAttach: boolean) {
    patch({ alwaysAttach })
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault()

    const conditions = []
    if (model.typeState.selectedIds.length > 0) {
      conditions.push({
        condition_field: CONDITION_FIELD_INCIDENT_TYPE,
        operator: model.typeState.operator,
        values: model.typeState.selectedIds,
      })
    }
    if (model.severityState.selectedIds.length > 0) {
      conditions.push({
        condition_field: CONDITION_FIELD_SEVERITY,
        operator: model.severityState.operator,
        values: model.severityState.selectedIds,
      })
    }
    for (const state of model.customFieldStates) {
      if (state.selectedIds.length === 0) {
        continue
      }
      conditions.push({
        condition_field: CONDITION_FIELD_CUSTOM_FIELD,
        operator: state.operator,
        values: state.selectedIds,
        incident_field_definition_id: state.fieldDefinitionId,
      })
    }

    const payload = {
      name: model.name,
      summary: model.summary,
      content: model.content,
      external_url: model.externalUrl,
      steps: model.steps.map((step) => ({ title: step.title, instruction: step.instruction })),
      conditions,
      always_attach: model.alwaysAttach,
    }

    const options = {
      preserveScroll: true,
      onStart: () => setProcessing(true),
      onFinish: () => setProcessing(false),
      onSuccess: () => onOpenChange(false),
      onError: (formErrors: Errors) => setErrors(formErrors),
    }

    if (runbook) {
      router.patch(runbookPath(runbook.id), payload, options)
    } else {
      router.post(runbooksPath(), payload, options)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[88vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? "Edit runbook" : "Add runbook"}</DialogTitle>
          <DialogDescription>
            {isEdit
              ? "Update the runbook content, steps, and matching conditions."
              : "Document a response procedure for your workspace."}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit}>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label htmlFor="runbook-name">Name</Label>
              <Input
                id="runbook-name"
                value={model.name}
                onChange={(event) => patch({ name: event.target.value })}
                placeholder="e.g. Database failover"
              />
              {errors.name && <p className="text-xs text-destructive">{errors.name}</p>}
            </div>

            <div className="space-y-2">
              <Label htmlFor="runbook-summary">Summary</Label>
              <Textarea
                id="runbook-summary"
                rows={2}
                value={model.summary}
                onChange={(event) => patch({ summary: event.target.value })}
                placeholder="Short description of when to use this runbook"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="runbook-content">Content</Label>
              <RunbookContentEditor
                value={model.content}
                onChange={(content) => patch({ content })}
                placeholder="Detailed procedure for this runbook"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="runbook-external-url">External URL</Label>
              <Input
                id="runbook-external-url"
                value={model.externalUrl}
                onChange={(event) => patch({ externalUrl: event.target.value })}
                placeholder="https://wiki.example.com/runbooks/failover (optional)"
              />
            </div>

            <RunbookStepsEditor steps={model.steps} onChange={(steps) => patch({ steps })} />

            <RunbookConditionsEditor
              typeState={model.typeState}
              severityState={model.severityState}
              customFieldStates={model.customFieldStates}
              incidentTypes={incidentTypes}
              severities={severities}
              customFields={customFields}
              onTypeChange={(typeState) => patch({ typeState })}
              onSeverityChange={(severityState) => patch({ severityState })}
              onCustomFieldStatesChange={(customFieldStates) => patch({ customFieldStates })}
            />

            <div className="flex items-start justify-between gap-4 rounded-lg border border-border px-4 py-3">
              <div className="space-y-1">
                <Label htmlFor="runbook-always-attach">Attach to every incident</Label>
                <p className="text-xs text-muted-foreground">
                  Without conditions or this, the runbook only appears when someone attaches it with{" "}
                  <span className="font-mono">/ff runbook</span>.
                </p>
              </div>
              <Switch
                id="runbook-always-attach"
                checked={model.alwaysAttach}
                onCheckedChange={setAlwaysAttach}
              />
            </div>
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>
              {isEdit ? "Save changes" : "Create runbook"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
