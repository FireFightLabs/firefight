import { useCallback, useEffect, useState } from "react"
import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Skeleton } from "@/components/ui/skeleton"
import { SearchableSelect } from "@/components/searchable-select"
import { SearchableMultiSelect } from "@/components/searchable-multi-select"
import { whenClosed } from "@/lib/handlers"
import {
  declareIncidentFormPath,
  declareIncidentPath,
  incidentFormPath,
  incidentLifecyclePath,
} from "@/lib/routes"
import type { IncidentPromptField } from "@/types/serializers"
import type { IncidentFormSlug } from "@/lib/generated/constants"

export type LifecycleForm = IncidentFormSlug

// Declaring has no incident behind it, so it reads and writes its own pair of
// paths. Everything else about the form is identical.
function readPath(incidentId: string | null, form: LifecycleForm) {
  return incidentId ? incidentFormPath(incidentId, form) : declareIncidentFormPath()
}

function writePath(incidentId: string | null, form: LifecycleForm) {
  return incidentId ? incidentLifecyclePath(incidentId, form) : declareIncidentPath()
}

type Answers = Record<string, string | string[]>

function initialAnswers(fields: IncidentPromptField[]): Answers {
  const answers: Answers = {}
  fields.forEach((field) => {
    if (field.value !== null && field.value !== undefined) {
      answers[field.key] = field.value
    }
  })
  return answers
}

// Which fields the form asks for is the server's answer, never the browser's.
// A dispatching field changing means re-resolving, because a condition or a
// terminal status can add or drop questions.
function useResolvedForm(incidentId: string | null, form: LifecycleForm, open: boolean) {
  const [fields, setFields] = useState<IncidentPromptField[] | null>(null)
  const [answers, setAnswers] = useState<Answers>({})

  const resolve = useCallback(
    async (currentAnswers: Answers) => {
      const url = new URL(readPath(incidentId, form), window.location.origin)
      Object.entries(currentAnswers).forEach(([key, value]) => {
        if (Array.isArray(value)) {
          value.forEach((entry) => url.searchParams.append(`answers[${key}][]`, entry))
        } else if (value) {
          url.searchParams.set(`answers[${key}]`, value)
        }
      })

      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) {
        return
      }

      const body = (await response.json()) as { fields: IncidentPromptField[] }
      setFields(body.fields)
      setAnswers((previous) => ({ ...initialAnswers(body.fields), ...previous }))
    },
    [incidentId, form],
  )

  useEffect(() => {
    if (!open) {
      setFields(null)
      setAnswers({})
      return
    }
    void resolve({})
  }, [open, resolve])

  return { fields, answers, setAnswers, resolve }
}

function FieldInput({
  field,
  value,
  onChange,
}: {
  field: IncidentPromptField
  value: string | string[] | undefined
  onChange: (next: string | string[]) => void
}) {
  const choices = (field.choices ?? []).map((choice) => ({ value: choice.value, label: choice.label }))

  if (field.input === "select" || field.input === "person") {
    return (
      <SearchableSelect
        value={typeof value === "string" && value ? value : null}
        onValueChange={(next) => onChange(next ?? "")}
        options={choices}
        placeholder={field.placeholder ?? "Select an option"}
        searchPlaceholder="Search..."
        emptyText="Nothing to pick"
      />
    )
  }

  if (field.input === "multi_select") {
    return (
      <SearchableMultiSelect
        value={Array.isArray(value) ? value : []}
        onValueChange={onChange}
        options={choices}
        placeholder={field.placeholder ?? "Select options"}
      />
    )
  }

  if (field.input === "long_text") {
    return (
      <Textarea
        rows={4}
        value={typeof value === "string" ? value : ""}
        placeholder={field.placeholder ?? ""}
        onChange={(event) => onChange(event.target.value)}
      />
    )
  }

  return (
    <Input
      type={field.input === "number" ? "number" : "text"}
      value={typeof value === "string" ? value : ""}
      placeholder={field.placeholder ?? ""}
      onChange={(event) => onChange(event.target.value)}
    />
  )
}

const TITLES: Record<LifecycleForm, { title: string; description: string; confirm: string }> = {
  declare: {
    title: "Declare an incident",
    description: "Firefight opens a channel for it and tells the people who need to know.",
    confirm: "Declare",
  },
  update: {
    title: "Post an update",
    description: "What responders and stakeholders will read, and where the incident stands now.",
    confirm: "Post update",
  },
  resolve: {
    title: "Resolve incident",
    description: "The response is over and this was a real incident.",
    confirm: "Resolve",
  },
  cancel: {
    title: "Cancel incident",
    description: "This turned out not to be an incident. It stays out of your time-to-resolve figures.",
    confirm: "Cancel incident",
  },
}

export function LifecycleFormDialog({
  incidentId,
  form,
  open,
  onOpenChange,
}: {
  // Null while declaring, since there is no incident yet.
  incidentId: string | null
  form: LifecycleForm
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const { fields, answers, setAnswers, resolve } = useResolvedForm(incidentId, form, open)
  const [saving, setSaving] = useState(false)
  const copy = TITLES[form]

  function close() {
    onOpenChange(false)
  }

  function change(field: IncidentPromptField, next: string | string[]) {
    const updated = { ...answers, [field.key]: next }
    setAnswers(updated)
    if (field.dispatches) {
      void resolve(updated)
    }
  }

  function submit(event: React.FormEvent) {
    event.preventDefault()
    setSaving(true)
    const options = {
      preserveScroll: true,
      onSuccess: close,
      onFinish: () => setSaving(false),
    }
    const path = writePath(incidentId, form)

    if (incidentId) {
      router.patch(path, { answers }, options)
    } else {
      router.post(path, { answers }, options)
    }
  }

  const missing = (fields ?? []).some((field) => {
    const value = answers[field.key]
    return field.required && (Array.isArray(value) ? value.length === 0 : !value)
  })

  return (
    <Dialog open={open} onOpenChange={whenClosed(close)}>
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{copy.title}</DialogTitle>
            <DialogDescription>{copy.description}</DialogDescription>
          </DialogHeader>

          <div className="flex max-h-[60vh] flex-col gap-4 overflow-y-auto py-4">
            {fields === null ? (
              <>
                <Skeleton className="h-16 w-full" />
                <Skeleton className="h-16 w-full" />
              </>
            ) : (
              fields.map((field) => (
                <div key={field.key} className="flex flex-col gap-1.5">
                  <Label>
                    {field.label}
                    {!field.required && <span className="ml-1.5 text-xs text-muted-foreground">Optional</span>}
                  </Label>
                  <FieldInput
                    field={field}
                    value={answers[field.key]}
                    onChange={(next) => change(field, next)}
                  />
                  {field.hint && <p className="text-xs leading-relaxed text-muted-foreground/80">{field.hint}</p>}
                </div>
              ))
            )}
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={close}>
              Never mind
            </Button>
            <Button type="submit" disabled={saving || fields === null || missing}>
              {copy.confirm}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
