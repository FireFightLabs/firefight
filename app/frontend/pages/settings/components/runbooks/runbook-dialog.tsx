import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import type { Errors } from "@inertiajs/core"

import type {
  IncidentSeveritySettings,
  IncidentTypeSettings,
  RunbookSettings,
} from "@/types/serializers"
import { runbookPath, runbooksPath } from "@/lib/routes"
import {
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
import { Textarea } from "@/components/ui/textarea"
import {
  RunbookStepsEditor,
  type EditableStep,
} from "@/pages/settings/components/runbooks/runbook-steps-editor"
import {
  RunbookConditionsEditor,
  type ConditionSectionState,
} from "@/pages/settings/components/runbooks/runbook-conditions-editor"

interface RunbookDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  runbook?: RunbookSettings | null
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
}

interface EditModel {
  name: string
  summary: string
  content: string
  externalUrl: string
  steps: EditableStep[]
  typeState: ConditionSectionState
  severityState: ConditionSectionState
}

function sectionState(runbook: RunbookSettings | null | undefined, field: string): ConditionSectionState {
  const condition = runbook?.conditions?.find((c) => c.conditionField === field)
  return {
    operator: condition?.operator ?? OPERATOR_ONE_OF,
    selectedIds: condition?.values ?? [],
  }
}

function initModel(runbook: RunbookSettings | null | undefined): EditModel {
  return {
    name: runbook?.name ?? "",
    summary: runbook?.summary ?? "",
    content: runbook?.content ?? "",
    externalUrl: runbook?.externalUrl ?? "",
    steps: (runbook?.steps ?? []).map((s) => ({
      key: crypto.randomUUID(),
      title: s.title,
      instruction: s.instruction ?? "",
    })),
    typeState: sectionState(runbook, CONDITION_FIELD_INCIDENT_TYPE),
    severityState: sectionState(runbook, CONDITION_FIELD_SEVERITY),
  }
}

export function RunbookDialog({ open, onOpenChange, runbook, incidentTypes, severities }: RunbookDialogProps) {
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

  function handleSubmit(e: FormEvent) {
    e.preventDefault()

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

    const payload = {
      name: model.name,
      summary: model.summary,
      content: model.content,
      external_url: model.externalUrl,
      steps: model.steps.map((s) => ({ title: s.title, instruction: s.instruction })),
      conditions,
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
                onChange={(e) => patch({ name: e.target.value })}
                placeholder="e.g. Database failover"
              />
              {errors.name && <p className="text-xs text-destructive">{errors.name}</p>}
            </div>

            <div className="space-y-2">
              <Label htmlFor="runbook-summary">Summary</Label>
              <Input
                id="runbook-summary"
                value={model.summary}
                onChange={(e) => patch({ summary: e.target.value })}
                placeholder="One-line description of when to use this runbook"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="runbook-content">Content (Markdown)</Label>
              <Textarea
                id="runbook-content"
                rows={6}
                className="font-mono text-xs"
                value={model.content}
                onChange={(e) => patch({ content: e.target.value })}
                placeholder="Detailed procedure in Markdown"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="runbook-external-url">External URL</Label>
              <Input
                id="runbook-external-url"
                value={model.externalUrl}
                onChange={(e) => patch({ externalUrl: e.target.value })}
                placeholder="https://wiki.example.com/runbooks/failover (optional)"
              />
            </div>

            <RunbookStepsEditor steps={model.steps} onChange={(steps) => patch({ steps })} />

            <RunbookConditionsEditor
              typeState={model.typeState}
              severityState={model.severityState}
              incidentTypes={incidentTypes}
              severities={severities}
              onTypeChange={(typeState) => patch({ typeState })}
              onSeverityChange={(severityState) => patch({ severityState })}
            />
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
