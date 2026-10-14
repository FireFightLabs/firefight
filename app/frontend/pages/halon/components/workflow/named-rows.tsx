import { IconPlus, IconX } from "@tabler/icons-react"
import type { ChangeEvent } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { ReferencePicker } from "@/components/tool-fields/reference-picker"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"

export interface NamedRow {
  key: string
  name: string
  text: string
}

export const ROW_NAME = /^[a-z][a-z0-9_]*$/

export function newRow(name = "", text = ""): NamedRow {
  return { key: crypto.randomUUID(), name, text }
}

interface NamedRowsProps {
  title: string
  rows: NamedRow[]
  limit: number
  namePlaceholder: string
  textPlaceholder: string
  textLabel: string
  addLabel: string
  // Offered beside each row's text, for a value that reads an earlier step.
  references?: SearchableSelectOption[]
  disabled: boolean
  onChange: (rows: NamedRow[]) => void
}

// A list of named rows, each a name later steps read it by and its text, such as Set data's values or the fields of a
// question's short form.
export function NamedRows({ title, rows, limit, namePlaceholder, textPlaceholder, textLabel, addLabel, references = [], disabled, onChange }: NamedRowsProps) {
  function update(key: string, patch: Partial<NamedRow>) {
    onChange(rows.map((row) => (row.key === key ? { ...row, ...patch } : row)))
  }

  function nameTyped(key: string) {
    return (event: ChangeEvent<HTMLInputElement>) => update(key, { name: event.target.value })
  }

  function textTyped(key: string) {
    return (event: ChangeEvent<HTMLInputElement>) => update(key, { text: event.target.value })
  }

  function inserted(row: NamedRow) {
    return (reference: string) => update(row.key, { text: `${row.text}${reference}` })
  }

  function add() {
    onChange([ ...rows, newRow() ])
  }

  function remove(key: string) {
    return () => onChange(rows.filter((row) => row.key !== key))
  }

  return (
    <section className="space-y-2">
      <h4 className="text-xs font-medium text-fg-secondary">{title}</h4>
      {rows.map((row) => (
        <div key={row.key} className="space-y-1.5 rounded-md border border-border p-2">
          <div className="flex gap-1.5">
            <Input value={row.name} onChange={nameTyped(row.key)} placeholder={namePlaceholder} aria-label="Name" disabled={disabled} className="font-mono text-xs" />
            {!disabled && (
              <button type="button" aria-label={`Remove ${row.name || "this row"}`} className="px-1 text-fg-muted hover:text-destructive" onClick={remove(row.key)}>
                <IconX className="size-4" />
              </button>
            )}
          </div>
          <div className="flex gap-1.5">
            <Input value={row.text} onChange={textTyped(row.key)} placeholder={textPlaceholder} aria-label={textLabel} disabled={disabled} />
            {references.length > 0 && !disabled && <ReferencePicker references={references} label={`Use an earlier value in ${row.name || "this value"}`} onPick={inserted(row)} />}
          </div>
        </div>
      ))}
      {!disabled && rows.length < limit && (
        <Button type="button" variant="outline" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={add}>
          <IconPlus className="size-3.5" />
          {addLabel}
        </Button>
      )}
    </section>
  )
}
