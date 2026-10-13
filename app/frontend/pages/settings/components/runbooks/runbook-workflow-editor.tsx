import type { ChangeEvent } from "react"
import type { ErrorValue } from "@inertiajs/core"
import { IconExternalLink } from "@tabler/icons-react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { workflowPath } from "@/lib/routes"
import { stateLabel } from "@/pages/halon/components/workflows/labels"
import type { RunbookWorkflowChoice } from "@/types/serializers"

const NO_WORKFLOW = ""

interface RunbookWorkflowEditorProps {
  workflowId: string
  savedName?: string
  aliasesText: string
  workflows: RunbookWorkflowChoice[] | null
  errors: Partial<Record<"workflow" | "aliases", ErrorValue>>
  onWorkflowChange: (workflowId: string) => void
  onAliasesChange: (aliasesText: string) => void
}

export function RunbookWorkflowEditor({ workflowId, savedName, aliasesText, workflows, errors, onWorkflowChange, onAliasesChange }: RunbookWorkflowEditorProps) {
  const options: SearchableSelectOption[] = [
    { value: NO_WORKFLOW, label: "None, people follow it by hand" },
    ...(workflows ?? []).map((workflow) => ({ value: workflow.id, label: workflow.name, group: stateLabel(workflow.state) })),
  ]
  const linkedName = (workflows ?? []).find((workflow) => workflow.id === workflowId)?.name ?? savedName ?? "the workflow"

  function choose(value: string | null) {
    onWorkflowChange(value ?? NO_WORKFLOW)
  }

  function typedAliases(event: ChangeEvent<HTMLInputElement>) {
    onAliasesChange(event.target.value)
  }

  return (
    <div className="space-y-4 rounded-lg border border-border px-4 py-3">
      <div className="space-y-1">
        <Label htmlFor="runbook-workflow">Workflow</Label>
        <p className="text-xs text-muted-foreground">
          Run it on this runbook starts the workflow you link here, in an incident, in its channel or when someone asks Halon by
          its name. The workflow runs as itself with only what an admin granted it, and what it does is changed on its page.
        </p>
      </div>
      <SearchableSelect
        id="runbook-workflow"
        value={workflowId}
        onValueChange={choose}
        options={withSavedWorkflow(options, workflowId, linkedName)}
        placeholder={workflows ? "None, people follow it by hand" : "Loading workflows"}
        searchPlaceholder="Search workflows"
        emptyText="No workflow by that name"
      />
      {workflowId !== NO_WORKFLOW && (
        <a
          href={workflowPath(workflowId)}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 text-sm text-link hover:underline"
        >
          <IconExternalLink className="size-3.5" />
          Open {linkedName} on its page
        </a>
      )}
      {errors.workflow && <p className="text-xs text-destructive">{errors.workflow}</p>}

      <div className="space-y-2">
        <Label htmlFor="runbook-aliases">Other names</Label>
        <Input
          id="runbook-aliases"
          value={aliasesText}
          onChange={typedAliases}
          placeholder="release firefight, ship it (separated by commas, optional)"
        />
        {errors.aliases && <p className="text-xs text-destructive">{errors.aliases}</p>}
      </div>
    </div>
  )
}

function withSavedWorkflow(options: SearchableSelectOption[], workflowId: string, name: string): SearchableSelectOption[] {
  if (workflowId === NO_WORKFLOW || options.some((option) => option.value === workflowId)) {
    return options
  }
  return [ { value: workflowId, label: name }, ...options ]
}
