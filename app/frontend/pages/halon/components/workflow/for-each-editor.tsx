import { type ChangeEvent, useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { ReferencePicker } from "@/components/tool-fields/reference-picker"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { WORKFLOW_CONFIG_KEYS, WORKFLOW_MAX_CONCURRENCY } from "@/lib/generated/constants"
import { jsonValue, REFERENCE, written, type JsonObject } from "@/lib/tool-fields"

const KEYS = WORKFLOW_CONFIG_KEYS
const WHOLE = /^\s*\d+\s*$/

interface ForEachEditorProps {
  idPrefix: string
  config: JsonObject
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

function itemsText(value: unknown): string {
  if (value === undefined || value === null) {
    return ""
  }
  return typeof value === "string" ? value : written(value)
}

// A list written as JSON stays a list, and anything else is the reference it reads the list from.
function itemsValue(entered: string): JsonObject[string] {
  const trimmed = entered.trim()
  if (trimmed.startsWith("[")) {
    try {
      const parsed: unknown = JSON.parse(trimmed)
      if (Array.isArray(parsed)) {
        return parsed.map(jsonValue)
      }
    } catch {
      return trimmed
    }
  }
  return trimmed
}

function forEachError(items: string, concurrency: string): string | null {
  const trimmed = items.trim()
  if (!trimmed) {
    return "Say which list it goes through, such as {{steps.find.services}}."
  }
  if (!trimmed.startsWith("[") && !REFERENCE.test(trimmed)) {
    return "Name the list with a value from an earlier step, or write it as a list such as [\"web\", \"api\"]."
  }
  const count = concurrency.trim()
  if (count && (!WHOLE.test(count) || Number(count) < 1 || Number(count) > WORKFLOW_MAX_CONCURRENCY)) {
    return `Run from 1 to ${WORKFLOW_MAX_CONCURRENCY} items at once.`
  }
  return null
}

// What a for each goes through and how many items it runs at once. The steps it runs for each item are drawn inside its
// box on the canvas and added by dropping steps into it.
export function ForEachEditor({ idPrefix, config, references, disabled, onChange }: ForEachEditorProps) {
  const [ items, setItems ] = useState(() => itemsText(config[KEYS.ITEMS]))
  const [ concurrency, setConcurrency ] = useState(() => itemsText(config[KEYS.CONCURRENCY]))

  function send(nextItems: string, nextConcurrency: string) {
    const count = nextConcurrency.trim()
    const next: JsonObject = { ...config, [KEYS.ITEMS]: itemsValue(nextItems) }
    next[KEYS.CONCURRENCY] = WHOLE.test(count) ? Number(count) : count ? count : null
    onChange(next, forEachError(nextItems, nextConcurrency))
  }

  function itemsTyped(event: ChangeEvent<HTMLInputElement>) {
    setItems(event.target.value)
    send(event.target.value, concurrency)
  }

  function inserted(reference: string) {
    setItems(reference)
    send(reference, concurrency)
  }

  function concurrencyTyped(event: ChangeEvent<HTMLInputElement>) {
    setConcurrency(event.target.value)
    send(items, event.target.value)
  }

  const error = forEachError(items, concurrency)

  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-items`} className="text-xs">The list it goes through</Label>
        <div className="flex gap-1.5">
          <Input id={`${idPrefix}-items`} value={items} onChange={itemsTyped} placeholder="{{steps.find.services}}" disabled={disabled} className="font-mono text-xs" />
          {!disabled && <ReferencePicker references={references} label="Go through a list an earlier step gave" onPick={inserted} />}
        </div>
      </div>
      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-concurrency`} className="text-xs">Items at once</Label>
        <Input id={`${idPrefix}-concurrency`} value={concurrency} onChange={concurrencyTyped} inputMode="numeric" placeholder="1" disabled={disabled} className="w-24" />
      </div>
      <p className="text-xs text-fg-muted">Steps dropped into its box on the canvas run once for each item, and read it as {"{{item}}"}.</p>
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
