import { useMemo, useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { WatchSpecEditor } from "@/components/watch/watch-spec-editor"
import type { JsonObject } from "@/lib/tool-fields"
import { sentWatch, watchError, watchState, type WatchState, type WatchTool } from "@/lib/watch-spec"
import { useCanvasChoices } from "@/pages/halon/hooks/use-canvas-choices"
import type { WorkflowToolChoice } from "@/types/serializers"

const NO_STEPS = "Add at least one thing to watch."

interface WatchEditorProps {
  idPrefix: string
  config: JsonObject
  // Undefined while the tools load.
  tools: WorkflowToolChoice[] | undefined
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

function watchTool(tool: WorkflowToolChoice): WatchTool {
  return { name: tool.name, group: tool.group, description: tool.description, reads: tool.readOnly, fields: tool.fields, watchFields: tool.watchFields ?? null }
}

// A Watch step: what it follows, written as a runbook's watch is, with a step's earlier values where a fixed one would
// go. The run waits while it watches and takes the route named for how it ended.
export function WatchEditor({ idPrefix, config, tools, references, disabled, onChange }: WatchEditorProps) {
  const [ watch, setWatch ] = useState<WatchState>(() => ({ ...watchState(config), on: true }))
  const { places, watchReads } = useCanvasChoices()
  const watchTools = useMemo(() => (tools ? tools.map(watchTool) : null), [ tools ])

  function changed(next: WatchState) {
    setWatch(next)
    onChange(sentWatch(next) ?? {}, watchError(next, NO_STEPS))
  }

  return (
    <WatchSpecEditor idPrefix={idPrefix} watch={watch} reads={watchReads} tools={watchTools} placeholders={references} places={places}
      disabled={disabled} onChange={changed} />
  )
}
