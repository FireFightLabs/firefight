import { IconX } from "@tabler/icons-react"
import type { ChangeEvent } from "react"

import { SearchableMultiSelect } from "@/components/searchable-multi-select"
import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { WATCH_SPEC_KEYS } from "@/lib/generated/constants"
import { NewDeployFields } from "@/components/watch/new-deploy-fields"
import { ToolFields } from "@/components/tool-fields/tool-fields"
import type { ArgumentsState } from "@/lib/tool-fields"
import { newDeployOf, stepText, type WatchStepState, type WatchTool } from "@/lib/watch-spec"

interface WatchStepEditorProps {
  number: number
  step: WatchStepState
  // The steps before it, which it may wait for, by key and as they are named.
  earlier: SearchableSelectOption[]
  history: boolean
  // The read tool the step names, or null for a capability or one this person cannot see.
  tool: WatchTool | null
  toolsLoaded: boolean
  readOptions: SearchableSelectOption[]
  selectedRead: string
  resourceOptions: SearchableSelectOption[]
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  onChange: (field: string, entered: string | boolean) => void
  onChooseRead: (name: string) => void
  onArgsChange: (args: ArgumentsState) => void
  onWaitsChange: (waitsFor: string[], keptWaits: string[]) => void
  onNewDeployTurn: (on: boolean) => void
  onNewDeployChange: (key: string, entered: string) => void
  onRemove: () => void
}

const KEPT_WAIT = "saved:"

// One thing a watch follows: a capability on a resource from the map, or any read tool Halon can make in a chat with its
// arguments, and what counts as done. A run in a resource's history ends on its own status.
export function WatchStepEditor({
  number, step, earlier, history, tool, toolsLoaded, readOptions, selectedRead, resourceOptions, placeholders, places, onChange, onChooseRead, onArgsChange,
  onWaitsChange, onNewDeployTurn, onNewDeployChange, onRemove,
}: WatchStepEditorProps) {
  const spec = step.spec
  const toolName = stepText(spec, WATCH_SPEC_KEYS.TOOL)
  const resource = stepText(spec, WATCH_SPEC_KEYS.RESOURCE)
  // An item left without a name is named after what it reads, as the server names it when the runbook runs.
  const read = readOptions.find((option) => option.value === selectedRead)
  const namePlaceholder = read ? `Name (optional), ${read.label} if left empty` : "Name (optional)"
  const resources = resource && !resourceOptions.some((option) => option.value === resource)
    ? [ { value: resource, label: resource }, ...resourceOptions ]
    : resourceOptions
  // A saved read the picker does not offer, such as a tool this person cannot see, still shows as chosen.
  const reads = selectedRead && !read ? [ { value: selectedRead, label: selectedRead }, ...readOptions ] : readOptions

  function typed(field: string) {
    return (event: ChangeEvent<HTMLInputElement>) => onChange(field, event.target.value)
  }

  function chosen(field: string) {
    return (value: string | null) => onChange(field, value ?? "")
  }

  function chooseRead(value: string | null) {
    if (value) {
      onChooseRead(value)
    }
  }

  function reportStart(checked: boolean) {
    onChange(WATCH_SPEC_KEYS.REPORT_START, checked)
  }

  // What was saved naming no step here stays chosen under its saved words until it is taken off.
  const keptOptions = step.keptWaits.map((ref) => ({ value: `${KEPT_WAIT}${ref}`, label: ref }))
  const waits = [ ...step.waitsFor, ...keptOptions.map((option) => option.value) ]

  function chooseWaits(values: string[]) {
    const kept = values.filter((value) => value.startsWith(KEPT_WAIT)).map((value) => value.slice(KEPT_WAIT.length))
    onWaitsChange(values.filter((value) => !value.startsWith(KEPT_WAIT)), kept)
  }

  return (
    <div className="space-y-2 rounded-md border border-border/60 p-2.5">
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium">Watch {number}</span>
        <button type="button" aria-label={`Remove watch ${number}`} className="text-fg-muted hover:text-destructive" onClick={onRemove}>
          <IconX className="size-4" />
        </button>
      </div>
      <Input aria-label={`Watch ${number} label`} value={stepText(spec, WATCH_SPEC_KEYS.LABEL)} onChange={typed(WATCH_SPEC_KEYS.LABEL)} placeholder={namePlaceholder} />
      <div className={toolName ? "grid gap-2" : "grid gap-2 sm:grid-cols-2"}>
        <SearchableSelect
          value={selectedRead || null}
          onValueChange={chooseRead}
          options={reads}
          placeholder="How to check it"
          searchPlaceholder="Search reads and read tools"
          emptyText="No read by that name"
        />
        {!toolName && (
          <SearchableSelect
            value={resource || null}
            onValueChange={chosen(WATCH_SPEC_KEYS.RESOURCE)}
            options={resources}
            placeholder="On which resource"
            searchPlaceholder="Search the map"
            emptyText="Nothing on the map by that name"
          />
        )}
      </div>
      {toolName && (
        <div className="space-y-2 rounded-md border border-border/60 px-3 py-2.5">
          {tool && <p className="text-xs text-muted-foreground">{tool.description}</p>}
          {toolsLoaded && !tool && (
            <p className="text-xs text-muted-foreground">
              {toolName} is not among the read tools you can use here, so its arguments are kept as they were saved.
            </p>
          )}
          <ToolFields
            idPrefix={`watch-${step.key}`}
            fields={tool ? tool.watchFields ?? tool.fields : null}
            state={step.args}
            errors={{}}
            placeholders={placeholders}
            places={places}
            onChange={onArgsChange}
          />
          <div className="space-y-1">
            <Label htmlFor={`watch-${step.key}-focus`} className="text-xs">Part of the answer to watch</Label>
            <Input
              id={`watch-${step.key}-focus`}
              value={stepText(spec, WATCH_SPEC_KEYS.FOCUS)}
              onChange={typed(WATCH_SPEC_KEYS.FOCUS)}
              placeholder="Such as data.status (optional)"
            />
            <p className="text-xs text-muted-foreground">
              For a long answer, the path to the part that says how it stands. Left empty, Halon reads the whole answer.
            </p>
          </div>
        </div>
      )}
      {history ? (
        <div className="space-y-2">
          <div className="grid gap-2 sm:grid-cols-2">
            <Input aria-label={`Watch ${number} run name`} value={stepText(spec, WATCH_SPEC_KEYS.NAME)} onChange={typed(WATCH_SPEC_KEYS.NAME)} placeholder="Only runs named, such as release (optional)" />
            <Input aria-label={`Watch ${number} run`} value={stepText(spec, WATCH_SPEC_KEYS.RUN)} onChange={typed(WATCH_SPEC_KEYS.RUN)} placeholder="A run by its id, number or name (optional)" />
          </div>
          <div className="flex items-center gap-2">
            <Switch id={`watch-${number}-report-start`} checked={spec[WATCH_SPEC_KEYS.REPORT_START] === true} onCheckedChange={reportStart} />
            <Label htmlFor={`watch-${number}-report-start`} className="text-xs font-normal">Also say when it starts</Label>
          </div>
        </div>
      ) : (
        <div className="grid gap-2 sm:grid-cols-2">
          <Input aria-label={`Watch ${number} done when`} value={stepText(spec, WATCH_SPEC_KEYS.DONE_WHEN)} onChange={typed(WATCH_SPEC_KEYS.DONE_WHEN)} placeholder="Done when it shows, such as status success" />
          <Input aria-label={`Watch ${number} failed when`} value={stepText(spec, WATCH_SPEC_KEYS.FAILED_WHEN)} onChange={typed(WATCH_SPEC_KEYS.FAILED_WHEN)} placeholder="Failed when it shows, such as crashed" />
          <Input aria-label={`Watch ${number} goal`} className="sm:col-span-2" value={stepText(spec, WATCH_SPEC_KEYS.GOAL)} onChange={typed(WATCH_SPEC_KEYS.GOAL)} placeholder="Or the question in a sentence, such as workflow release's newest run finished" />
        </div>
      )}
      {(earlier.length > 0 || keptOptions.length > 0) && (
        <div className="space-y-1">
          <Label className="text-xs">Waits for</Label>
          <SearchableMultiSelect
            value={waits}
            onValueChange={chooseWaits}
            options={[ ...earlier, ...keptOptions ]}
            placeholder="Nothing, it starts at once"
            searchPlaceholder="Search the items above"
            emptyText="No item above by that name"
          />
          <p className="text-xs text-muted-foreground">
            Halon starts checking it once these succeeded, and counts only what came after them. If one fails, it is skipped.
          </p>
        </div>
      )}
      {!history && (
        <NewDeployFields
          id={`watch-${step.key}`}
          number={number}
          newDeploy={newDeployOf(spec)}
          askResource={Boolean(toolName)}
          resourceOptions={resourceOptions}
          onTurn={onNewDeployTurn}
          onChange={onNewDeployChange}
        />
      )}
    </div>
  )
}
