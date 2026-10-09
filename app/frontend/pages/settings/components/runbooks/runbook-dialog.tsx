import { useEffect, useState, type FormEvent } from "react"
import { router, usePage } from "@inertiajs/react"
import type { Errors, VisitOptions } from "@inertiajs/core"

import type {
  IncidentSeveritySettings,
  IncidentTypeSettings,
  RunbookCustomField,
  RunbookPlace,
  RunbookSettings,
  RunbookToolChoice,
  RunbookWatchRead,
} from "@/types/serializers"
import type { SearchableSelectOption } from "@/components/searchable-select"
import { RUNBOOK_CHOICE_PROPS } from "@/lib/generated/constants"
import type { SharedProps } from "@/types"
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
import { RunbookProcedureEditor } from "@/pages/settings/components/runbooks/runbook-procedure-editor"
import {
  argumentsState,
  fieldErrors,
  inputPlaceholders,
  procedurePayload,
  procedureState,
  watchError,
  type ProcedureState,
} from "@/pages/settings/lib/runbook-procedure"
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
  procedure: ProcedureState
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
      key: step.id,
      id: step.id,
      title: step.title,
      instruction: step.instruction ?? "",
      tool: step.tool ?? "",
      args: argumentsState(step.arguments),
    })),
    typeState: sectionState(runbook, CONDITION_FIELD_INCIDENT_TYPE),
    severityState: sectionState(runbook, CONDITION_FIELD_SEVERITY),
    customFieldStates: customFieldStates(runbook),
    alwaysAttach: runbook?.alwaysAttach ?? false,
    procedure: procedureState(runbook),
  }
}

// What the editor builds steps and the watch from, which the page sends only once asked.
interface ChoiceProps extends SharedProps {
  [RUNBOOK_CHOICE_PROPS.TOOL_CHOICES]?: RunbookToolChoice[]
  [RUNBOOK_CHOICE_PROPS.WATCH_READS]?: RunbookWatchRead[]
  [RUNBOOK_CHOICE_PROPS.PLACES]?: RunbookPlace[]
}

const CHOICES = Object.values(RUNBOOK_CHOICE_PROPS)

function loadChoices() {
  router.reload({ only: CHOICES })
}

export function RunbookDialog({ open, onOpenChange, runbook, incidentTypes, severities, customFields }: RunbookDialogProps) {
  const isEdit = Boolean(runbook)
  const { toolChoices, watchReads, places } = usePage<ChoiceProps>().props
  const tools = toolChoices ?? null
  const reads = watchReads ?? null
  const [model, setModel] = useState<EditModel>(() => initModel(runbook))
  const [errors, setErrors] = useState<Errors>({})
  const [stepErrors, setStepErrors] = useState<Record<string, Record<string, string>>>({})
  const [processing, setProcessing] = useState(false)
  const [wasOpen, setWasOpen] = useState(open)

  if (open !== wasOpen) {
    setWasOpen(open)
    if (open) {
      setModel(initModel(runbook))
      setErrors({})
    }
  }

  useEffect(() => {
    if (open) {
      loadChoices()
    }
  }, [ open ])

  const placeholders: SearchableSelectOption[] = inputPlaceholders(model.procedure.inputs)
  const placeOptions: SearchableSelectOption[] = (places ?? []).map((place) => ({ value: place.name, label: place.name, group: place.kind }))
  const watchProblem = watchError(model.procedure.watch)
  const [ shownWatchProblem, setShownWatchProblem ] = useState<string | null>(null)

  // A server error outlives the value that caused it, so it is cleared once the
  // field changes.
  useEffect(() => {
    setErrors({})
    setStepErrors({})
    setShownWatchProblem(null)
  }, [model])

  // The page comes back without the pickers' choices, which it loads only on request, so they are asked for again to keep
  // showing what was picked beside the error.
  function showErrors(formErrors: Errors) {
    setErrors(formErrors)
    loadChoices()
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

    const problems = stepProblems(model.steps, tools)
    if (Object.keys(problems).length > 0 || watchProblem) {
      setStepErrors(problems)
      setShownWatchProblem(watchProblem)
      return
    }
    const procedure = procedurePayload(model.procedure)

    const payload = {
      name: model.name,
      summary: model.summary,
      content: model.content,
      external_url: model.externalUrl,
      steps: model.steps.map(sentStep),
      conditions,
      always_attach: model.alwaysAttach,
      inputs: procedure.inputs,
      aliases: procedure.aliases,
      watch: procedure.watch,
    }

    const options: VisitOptions = {
      preserveState: "errors",
      preserveScroll: true,
      onStart: () => setProcessing(true),
      onFinish: () => setProcessing(false),
      onSuccess: () => onOpenChange(false),
      onError: showErrors,
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

            <RunbookStepsEditor
              steps={model.steps}
              stepErrors={stepErrors}
              tools={tools}
              placeholders={placeholders}
              places={placeOptions}
              onChange={(steps) => patch({ steps })}
            />
            {(errors.tool || errors.arguments) && <p className="text-xs text-destructive">{errors.tool ?? errors.arguments}</p>}

            <RunbookProcedureEditor
              state={model.procedure}
              errors={{ aliases: errors.aliases, inputs: errors.inputs, watch: errors.watch }}
              watchError={shownWatchProblem}
              reads={reads}
              placeholders={placeholders}
              places={placeOptions}
              onChange={(procedure) => patch({ procedure })}
            />

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

// What is wrong with each step's fields, by the step's key, checked against the tool's own fields once they loaded.
function stepProblems(steps: EditableStep[], tools: RunbookToolChoice[] | null): Record<string, Record<string, string>> {
  const problems: Record<string, Record<string, string>> = {}
  steps.forEach((step) => {
    const choice = tools?.find((tool) => tool.name === step.tool)
    const found = choice ? fieldErrors(choice.fields, step.args) : {}
    if (Object.keys(found).length > 0) {
      problems[step.key] = found
    }
  })
  return problems
}

function sentStep(step: EditableStep) {
  const tool = step.tool.trim()
  return { id: step.id, title: step.title, instruction: step.instruction, tool: tool.length > 0 ? tool : null, arguments: tool.length > 0 ? step.args.values : {} }
}
