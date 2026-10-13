import type { SearchableSelectOption } from "@/components/searchable-select"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { WatchSpecEditor } from "@/components/watch/watch-spec-editor"
import { firstWatchStep, type WatchState } from "@/lib/watch-spec"
import type { RunbookToolChoice, RunbookWatchRead } from "@/types/serializers"

interface RunbookWatchEditorProps {
  watch: WatchState
  reads: RunbookWatchRead[] | null
  tools: RunbookToolChoice[] | null
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  error: string | null
  serverErrors: string[]
  onChange: (watch: WatchState) => void
}

// What Halon watches once every step went through, turned on or off, and what it follows when on.
export function RunbookWatchEditor({ watch, reads, tools, placeholders, places, error, serverErrors, onChange }: RunbookWatchEditorProps) {
  function turn(on: boolean) {
    const steps = on && watch.steps.length === 0 ? [ firstWatchStep(reads) ] : watch.steps
    onChange({ ...watch, on, steps })
  }

  return (
    <div className="space-y-3">
      <div className="flex items-start justify-between gap-4">
        <div className="space-y-1">
          <Label htmlFor="runbook-watch-on">Watch afterwards</Label>
          <p className="text-xs text-muted-foreground">
            Once every step went through, Halon follows these and reports back in the chat and by direct message.
          </p>
        </div>
        <Switch id="runbook-watch-on" checked={watch.on} onCheckedChange={turn} />
      </div>
      {watch.on && (
        <WatchSpecEditor idPrefix="runbook-watch" watch={watch} reads={reads} tools={tools} placeholders={placeholders} places={places} onChange={onChange} />
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
      {serverErrors.map((sentence, index) => (
        <p key={index} className="text-xs text-destructive">{sentence}</p>
      ))}
    </div>
  )
}
