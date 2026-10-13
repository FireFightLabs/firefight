import { IconPlus, IconX } from "@tabler/icons-react"
import { type ChangeEvent, useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { ReferencePicker } from "@/components/tool-fields/reference-picker"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { WORKFLOW_ASK_HALON } from "@/lib/generated/constants"
import { isObject, type JsonObject } from "@/lib/tool-fields"

const FIELD_NAME = /^[a-z0-9_]+$/

interface FieldDraft {
  key: string
  name: string
  description: string
}

interface AskHalonEditorProps {
  idPrefix: string
  config: JsonObject
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

function fieldDrafts(config: JsonObject): FieldDraft[] {
  const saved = config[WORKFLOW_ASK_HALON.FIELDS]
  return (Array.isArray(saved) ? saved : []).filter(isObject).map((field) => ({
    key: crypto.randomUUID(),
    name: String(field[WORKFLOW_ASK_HALON.FIELD_NAME] ?? ""),
    description: String(field[WORKFLOW_ASK_HALON.FIELD_DESCRIPTION] ?? ""),
  }))
}

function askError(question: string, fields: FieldDraft[]): string | null {
  if (!question.trim()) {
    return "Say what Halon answers."
  }
  if (fields.length > WORKFLOW_ASK_HALON.FIELD_LIMIT) {
    return `Ask for at most ${WORKFLOW_ASK_HALON.FIELD_LIMIT} fields.`
  }
  return fields.some((field) => !FIELD_NAME.test(field.name.trim())) ? "Name each field in lowercase letters, numbers and underscores." : null
}

// An Ask Halon step: the question Halon answers, the data it judges, usually a value from an earlier step, and any field
// it answers beside its verdict and summary, each read by later steps as {{steps.<name>.<field>}}.
export function AskHalonEditor({ idPrefix, config, references, disabled, onChange }: AskHalonEditorProps) {
  const [ question, setQuestion ] = useState(() => String(config[WORKFLOW_ASK_HALON.QUESTION] ?? ""))
  const [ data, setData ] = useState(() => String(config[WORKFLOW_ASK_HALON.DATA] ?? ""))
  const [ fields, setFields ] = useState<FieldDraft[]>(() => fieldDrafts(config))

  function send(nextQuestion: string, nextData: string, nextFields: FieldDraft[]) {
    const asked = nextFields.map((field) => ({ [WORKFLOW_ASK_HALON.FIELD_NAME]: field.name.trim(), [WORKFLOW_ASK_HALON.FIELD_DESCRIPTION]: field.description.trim() }))
    onChange({ ...config, [WORKFLOW_ASK_HALON.QUESTION]: nextQuestion, [WORKFLOW_ASK_HALON.DATA]: nextData, [WORKFLOW_ASK_HALON.FIELDS]: asked },
      askError(nextQuestion, nextFields))
  }

  function questionTyped(event: ChangeEvent<HTMLTextAreaElement>) {
    setQuestion(event.target.value)
    send(event.target.value, data, fields)
  }

  function dataTyped(event: ChangeEvent<HTMLInputElement>) {
    setData(event.target.value)
    send(question, event.target.value, fields)
  }

  function insertData(reference: string) {
    setData(`${data}${reference}`)
    send(question, `${data}${reference}`, fields)
  }

  function updateField(key: string, patch: Partial<FieldDraft>) {
    const next = fields.map((field) => (field.key === key ? { ...field, ...patch } : field))
    setFields(next)
    send(question, data, next)
  }

  function fieldTyped(key: string, part: "name" | "description") {
    return (event: ChangeEvent<HTMLInputElement>) => updateField(key, { [part]: event.target.value })
  }

  function addField() {
    const next = [ ...fields, { key: crypto.randomUUID(), name: "", description: "" } ]
    setFields(next)
    send(question, data, next)
  }

  function removeField(key: string) {
    return () => {
      const next = fields.filter((field) => field.key !== key)
      setFields(next)
      send(question, data, next)
    }
  }

  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-question`} className="text-xs">Question<span className="text-destructive"> *</span></Label>
        <Textarea id={`${idPrefix}-question`} value={question} onChange={questionTyped} disabled={disabled} rows={3}
          placeholder="Did the error rate settle after the change?" />
      </div>
      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-data`} className="text-xs">What it judges</Label>
        <div className="flex gap-1.5">
          <Input id={`${idPrefix}-data`} value={data} onChange={dataTyped} disabled={disabled} placeholder="{{steps.check.answer}}" />
          {references.length > 0 && !disabled && <ReferencePicker references={references} label="Use an earlier value in what it judges" onPick={insertData} />}
        </div>
        <p className="text-xs text-muted-foreground">Halon reads only this, and answers ok, problem or unsure with a summary.</p>
      </div>
      <section className="space-y-2">
        <h4 className="text-xs font-medium text-fg-secondary">Fields it answers</h4>
        {fields.map((field) => (
          <div key={field.key} className="flex gap-1.5">
            <Input value={field.name} onChange={fieldTyped(field.key, "name")} placeholder="service" aria-label="Field name" disabled={disabled} className="w-36 font-mono text-xs" />
            <Input value={field.description} onChange={fieldTyped(field.key, "description")} placeholder="Which service it is about" aria-label="What the field holds" disabled={disabled} />
            {!disabled && (
              <button type="button" aria-label={`Remove ${field.name || "this field"}`} className="px-1 text-fg-muted hover:text-destructive" onClick={removeField(field.key)}>
                <IconX className="size-4" />
              </button>
            )}
          </div>
        ))}
        {!disabled && fields.length < WORKFLOW_ASK_HALON.FIELD_LIMIT && (
          <Button type="button" variant="outline" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={addField}>
            <IconPlus className="size-3.5" />
            Add a field
          </Button>
        )}
      </section>
    </div>
  )
}
