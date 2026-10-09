import type { ErrorValue } from "@inertiajs/core"
import { IconPlus, IconX } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import type { SearchableSelectOption } from "@/components/searchable-select"
import { RunbookWatchEditor } from "@/pages/settings/components/runbooks/runbook-watch-editor"
import type { EditableInput, ProcedureState, WatchState } from "@/pages/settings/lib/runbook-procedure"
import type { RunbookWatchRead } from "@/types/serializers"

interface RunbookProcedureEditorProps {
  state: ProcedureState
  errors: Partial<Record<"aliases" | "inputs" | "watch", ErrorValue>>
  watchError: string | null
  reads: RunbookWatchRead[] | null
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  onChange: (state: ProcedureState) => void
}

// What lets Halon run the runbook by name: other names people call it, what to ask each time, and what to watch once
// every step went through. A runbook that leaves all of it empty is an ordinary incident runbook.
export function RunbookProcedureEditor({ state, errors, watchError, reads, placeholders, places, onChange }: RunbookProcedureEditorProps) {
  function patch(next: Partial<ProcedureState>) {
    onChange({ ...state, ...next })
  }

  function setWatch(watch: WatchState) {
    patch({ watch })
  }

  function updateInput(index: number, next: Partial<EditableInput>) {
    patch({ inputs: state.inputs.map((input, position) => (position === index ? { ...input, ...next } : input)) })
  }

  function addInput() {
    patch({ inputs: [ ...state.inputs, { key: crypto.randomUUID(), name: "", question: "", defaultValue: "" } ] })
  }

  function removeInput(index: number) {
    patch({ inputs: state.inputs.filter((_input, position) => position !== index) })
  }

  return (
    <div className="space-y-4 rounded-lg border border-border px-4 py-3">
      <div className="space-y-1">
        <Label>Run by Halon</Label>
        <p className="text-xs text-muted-foreground">
          When a step names a tool, people can ask Halon to run this runbook by its name. Halon says what it will do, asks
          for each input and waits for a confirmation before any step runs.
        </p>
      </div>

      <div className="space-y-2">
        <Label htmlFor="runbook-aliases">Other names</Label>
        <Input
          id="runbook-aliases"
          value={state.aliasesText}
          onChange={(event) => patch({ aliasesText: event.target.value })}
          placeholder="release firefight, ship it (separated by commas, optional)"
        />
        {errors.aliases && <p className="text-xs text-destructive">{errors.aliases}</p>}
      </div>

      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <Label>Inputs</Label>
          <Button type="button" variant="outline" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={addInput}>
            <IconPlus className="size-3.5" />
            Add input
          </Button>
        </div>
        {state.inputs.length === 0 ? (
          <p className="text-xs text-muted-foreground">
            None. A step or the watch names an input as {"{{key}}"}, and Halon asks for it each time.
          </p>
        ) : (
          <div className="space-y-2">
            {state.inputs.map((input, index) => (
              <div key={input.key} className="flex items-start gap-2">
                <div className="grid flex-1 gap-2 sm:grid-cols-[6rem_1fr_6rem]">
                  <Input
                    aria-label={`Input ${index + 1} key`}
                    className="font-mono text-xs"
                    value={input.name}
                    onChange={(event) => updateInput(index, { name: event.target.value })}
                    placeholder="bump"
                  />
                  <Input
                    aria-label={`Input ${index + 1} question`}
                    value={input.question}
                    onChange={(event) => updateInput(index, { question: event.target.value })}
                    placeholder="Which version bump?"
                  />
                  <Input
                    aria-label={`Input ${index + 1} default`}
                    value={input.defaultValue}
                    onChange={(event) => updateInput(index, { defaultValue: event.target.value })}
                    placeholder="Default"
                  />
                </div>
                <button
                  type="button"
                  aria-label={`Remove input ${index + 1}`}
                  className="pt-2 text-fg-muted hover:text-destructive"
                  onClick={() => removeInput(index)}
                >
                  <IconX className="size-4" />
                </button>
              </div>
            ))}
          </div>
        )}
        {errors.inputs && <p className="text-xs text-destructive">{errors.inputs}</p>}
      </div>

      <RunbookWatchEditor
        watch={state.watch}
        reads={reads}
        placeholders={placeholders}
        places={places}
        error={watchError}
        serverErrors={errors.watch ?? []}
        onChange={setWatch}
      />
    </div>
  )
}
