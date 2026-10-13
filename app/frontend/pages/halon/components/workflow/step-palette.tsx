import { IconSearch } from "@tabler/icons-react"
import { type ChangeEvent, useMemo, useState } from "react"

import { Skeleton } from "@/components/ui/skeleton"
import { WORKFLOW_CALL_TOOL, WORKFLOW_STEP_GROUP, WORKFLOW_STEP_GROUPS } from "@/lib/generated/constants"
import { PaletteEntry } from "@/pages/halon/components/workflow/palette-entry"
import { StepIcon } from "@/pages/halon/components/workflow/step-icon"
import { TriggerIcon } from "@/pages/halon/components/workflow/trigger-icon"
import { GROUP_LABELS } from "@/pages/halon/lib/workflow/labels"
import { DRAG_TYPE, type PaletteChoice } from "@/pages/halon/lib/workflow/new-step"
import type { WorkflowStepKind, WorkflowToolChoice, WorkflowTriggerKind } from "@/types/serializers"

interface StepPaletteProps {
  stepKinds: WorkflowStepKind[]
  triggerKinds: WorkflowTriggerKind[]
  // Undefined while the tools load.
  tools: WorkflowToolChoice[] | undefined
  triggerKind: string
  disabled: boolean
  onAddStep: (choice: PaletteChoice) => void
  onChooseTrigger: (kind: WorkflowTriggerKind) => void
}

function matches(query: string, ...texts: string[]): boolean {
  return query.length === 0 || texts.some((text) => text.toLowerCase().includes(query))
}

// Everything a workflow can start from and do, grouped as the Steps table is, with each connection's tools under its own
// name and one search over all of it.
export function StepPalette({ stepKinds, triggerKinds, tools, triggerKind, disabled, onAddStep, onChooseTrigger }: StepPaletteProps) {
  const [ query, setQuery ] = useState("")
  const search = query.trim().toLowerCase()
  const callTool = stepKinds.find((kind) => kind.key === WORKFLOW_CALL_TOOL.KIND) ?? null

  const triggers = triggerKinds.filter((kind) => matches(search, kind.label, kind.description))
  const groups = useMemo(() => WORKFLOW_STEP_GROUPS.map((group) => ({
    group,
    kinds: stepKinds.filter((kind) => kind.group === group && kind.key !== WORKFLOW_CALL_TOOL.KIND && matches(search, kind.label, kind.description)),
  })).filter(({ kinds }) => kinds.length > 0), [ stepKinds, search ])
  const toolGroups = useMemo(() => {
    const found = new Map<string, WorkflowToolChoice[]>()
    for (const tool of tools ?? []) {
      if (matches(search, tool.name, tool.description, tool.group)) {
        found.set(tool.group, [ ...(found.get(tool.group) ?? []), tool ])
      }
    }
    return [ ...found.entries() ]
  }, [ tools, search ])
  const toolCount = tools?.length ?? 0
  const placeholder = `Search ${triggerKinds.length} ${triggerKinds.length === 1 ? "trigger" : "triggers"}, ${stepKinds.length - (callTool ? 1 : 0) + toolCount} steps`

  function typed(event: ChangeEvent<HTMLInputElement>) {
    setQuery(event.target.value)
  }

  const nothing = triggers.length === 0 && groups.length === 0 && toolGroups.length === 0 && (tools !== undefined || !callTool)

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="border-b border-border p-3">
        <h2 className="mb-2.5 font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">Add a step</h2>
        <label className="flex h-8 items-center gap-2 rounded-sm border border-border bg-surface-input px-2.5 focus-within:border-border-control">
          <IconSearch className="size-3.5 text-fg-muted" />
          <input
            type="search"
            value={query}
            onChange={typed}
            placeholder={placeholder}
            aria-label="Search triggers and steps"
            className="min-w-0 flex-1 border-0 bg-transparent p-0 text-[12.5px] text-fg-primary shadow-none outline-none placeholder:text-fg-disabled focus-visible:outline-none"
          />
        </label>
        {disabled && <p className="mt-2 text-[11.5px] text-fg-muted">Open the draft to add steps.</p>}
      </div>
      <div className="min-h-0 flex-1 space-y-0.5 overflow-y-auto p-1.5">
        {triggers.length > 0 && (
          <section>
            <h3 className="px-2 pt-2.5 pb-1 font-mono text-[10px] tracking-[0.08em] text-brand/70 uppercase">Triggers</h3>
            {triggers.map((kind) => (
              <PaletteEntry
                key={kind.key}
                icon={<TriggerIcon icon={kind.icon} size="sm" />}
                label={kind.label}
                description={kind.key === triggerKind ? "What starts this workflow now" : kind.description}
                disabled={disabled || kind.key === triggerKind}
                dragData={null}
                dragType={DRAG_TYPE}
                onPick={() => onChooseTrigger(kind)}
              />
            ))}
          </section>
        )}
        {groups.map(({ group, kinds }) => (
          <section key={group}>
            <h3 className="px-2 pt-2.5 pb-1 font-mono text-[10px] tracking-[0.08em] text-brand/70 uppercase">{GROUP_LABELS[group]}</h3>
            {kinds.map((kind) => (
              <PaletteEntry
                key={kind.key}
                icon={<StepIcon icon={kind.icon} halon={kind.group === WORKFLOW_STEP_GROUP.HALON} size="sm" />}
                label={kind.label}
                description={kind.description}
                disabled={disabled}
                dragData={JSON.stringify({ kind: kind.key, tool: null })}
                dragType={DRAG_TYPE}
                onPick={() => onAddStep({ kind, tool: null })}
              />
            ))}
          </section>
        ))}
        {callTool && tools === undefined && (
          <div className="space-y-1.5 px-2 pt-3" aria-label="Loading tools">
            <Skeleton className="h-3 w-20" />
            <Skeleton className="h-7 w-full" />
            <Skeleton className="h-7 w-full" />
          </div>
        )}
        {callTool && toolGroups.map(([ group, groupTools ]) => (
          <section key={group}>
            <h3 className="px-2 pt-2.5 pb-1 font-mono text-[10px] tracking-[0.08em] text-brand/70 uppercase">{group}</h3>
            {groupTools.map((tool) => (
              <PaletteEntry
                key={tool.name}
                icon={<StepIcon icon={callTool.icon} size="sm" />}
                label={tool.name}
                description={tool.description}
                grantNeeded={tool.grantNeeded}
                disabled={disabled}
                dragData={JSON.stringify({ kind: callTool.key, tool: tool.name })}
                dragType={DRAG_TYPE}
                onPick={() => onAddStep({ kind: callTool, tool })}
              />
            ))}
          </section>
        ))}
        {nothing && <p className="px-2 py-4 text-center text-xs text-fg-muted">Nothing matches {query.trim()}.</p>}
      </div>
    </div>
  )
}
