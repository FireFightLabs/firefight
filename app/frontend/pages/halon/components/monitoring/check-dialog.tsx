import { useState, type FormEvent } from "react"
import type { Errors } from "@inertiajs/core"
import { router } from "@inertiajs/react"

import { FormErrors } from "@/components/form-errors"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { CHECK_CADENCES, CHECK_KINDS } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { omitErrors } from "@/lib/form-errors"
import { investigationCheckPath, investigationChecksPath } from "@/lib/routes"
import type { InvestigationCheck } from "@/types/serializers"
import type { CheckChoice } from "@/pages/halon/components/monitoring/types"

export type CheckDialogState = { mode: "create" } | { mode: "edit"; check: InvestigationCheck } | null

const WEEKDAYS = [ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" ]
const HOURS = Array.from({ length: 24 }, (_unused, hour) => hour)
const DEFAULT_HOUR = 9
const MONDAY = 1

interface Draft {
  name: string
  kind: string
  notes: string
  cadence: string
  hour: number
  weekday: number
  timeZone: string
}

function browserTimeZone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone
}

const FIELDS_WITH_OWN_ERRORS = [ "name", "notes", "time_zone" ]

// One message for a field, however the server sent it.
function messageOf(errors: Errors, field: string): string | undefined {
  const message = errors[field]
  return Array.isArray(message) ? message[0] : message
}

function hourLabel(hour: number): string {
  return `${String(hour).padStart(2, "0")}:00`
}

function draftFor(check: InvestigationCheck | null): Draft {
  return {
    name: check?.name ?? "",
    kind: check?.kind ?? CHECK_KINDS.DISK,
    notes: check?.notes ?? "",
    cadence: check?.cadence ?? CHECK_CADENCES.DAILY,
    hour: check?.hour ?? DEFAULT_HOUR,
    weekday: check?.weekday ?? MONDAY,
    timeZone: check?.timeZone ?? browserTimeZone(),
  }
}

// Owns both create and edit, as every settings dialog does.
export function CheckDialog({
  state,
  onClose,
  kinds,
  cadences,
}: {
  state: CheckDialogState
  onClose: () => void
  kinds: CheckChoice[]
  cadences: CheckChoice[]
}) {
  const editing = state?.mode === "edit" ? state.check : null
  const [draft, setDraft] = useState<Draft>(() => draftFor(editing))
  const [errors, setErrors] = useState<Errors>({})
  const [processing, setProcessing] = useState(false)

  // Re-seed when the dialog opens, and when it is reused for a different row.
  const identity = `${state?.mode ?? "closed"}:${editing?.id ?? ""}`
  const [lastIdentity, setLastIdentity] = useState<string | null>(null)
  if (state && identity !== lastIdentity) {
    setLastIdentity(identity)
    setDraft(draftFor(editing))
    setErrors({})
  }

  const fieldId = (field: string) => `check-${field}-${editing?.id ?? "new"}`
  const chosenKind = kinds.find((kind) => kind.value === draft.kind)
  const custom = draft.kind === CHECK_KINDS.CUSTOM
  const weekly = draft.cadence === CHECK_CADENCES.WEEKLY

  function change<Key extends keyof Draft>(key: Key, value: Draft[Key]) {
    setDraft((current) => ({ ...current, [key]: value }))
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setProcessing(true)

    const params = {
      name: draft.name,
      kind: draft.kind,
      notes: draft.notes,
      cadence: draft.cadence,
      hour: draft.hour,
      weekday: weekly ? draft.weekday : null,
      time_zone: draft.timeZone,
    }
    const options = {
      preserveScroll: true,
      onSuccess: onClose,
      onError: (received: Errors) => setErrors(received),
      onFinish: () => setProcessing(false),
    }

    if (editing) {
      router.patch(investigationCheckPath(editing.id), params, options)
    } else {
      router.post(investigationChecksPath(), params, options)
    }
  }

  return (
    <Dialog open={Boolean(state)} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>{editing ? "Edit check" : "Add check"}</DialogTitle>
            <DialogDescription>
              Halon runs it on this schedule and tells the owning team about anything that will break if nobody acts.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4 py-4">
            <FormErrors errors={omitErrors(errors, ...FIELDS_WITH_OWN_ERRORS)} />
            <div className="flex flex-col gap-2">
              <Label htmlFor={fieldId("name")}>Name</Label>
              <Input
                id={fieldId("name")}
                placeholder="Disk space"
                value={draft.name}
                onChange={(event) => change("name", event.target.value)}
              />
              {messageOf(errors, "name") && <p className="text-xs text-destructive">{messageOf(errors, "name")}</p>}
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor={fieldId("kind")}>Looks at</Label>
              <Select value={draft.kind} onValueChange={(value) => change("kind", value)}>
                <SelectTrigger id={fieldId("kind")} className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {kinds.map((kind) => (
                    <SelectItem key={kind.value} value={kind.value}>{kind.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {chosenKind?.description && <p className="text-xs text-muted-foreground">{chosenKind.description}</p>}
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor={fieldId("notes")}>{custom ? "What to look at" : "Notes for Halon (optional)"}</Label>
              <Textarea
                id={fieldId("notes")}
                rows={3}
                placeholder={custom ? "The jobs queue in orders-db should never hold more than 1,000 jobs." : "Only production. Our objective is 99.9% over 30 days."}
                value={draft.notes}
                onChange={(event) => change("notes", event.target.value)}
              />
              {messageOf(errors, "notes") && <p className="text-xs text-destructive">{messageOf(errors, "notes")}</p>}
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <div className="flex flex-col gap-2">
                <Label htmlFor={fieldId("cadence")}>How often</Label>
                <Select value={draft.cadence} onValueChange={(value) => change("cadence", value)}>
                  <SelectTrigger id={fieldId("cadence")} className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {cadences.map((cadence) => (
                      <SelectItem key={cadence.value} value={cadence.value}>{cadence.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {weekly && (
                <div className="flex flex-col gap-2">
                  <Label htmlFor={fieldId("weekday")}>Day</Label>
                  <Select value={String(draft.weekday)} onValueChange={(value) => change("weekday", Number(value))}>
                    <SelectTrigger id={fieldId("weekday")} className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {WEEKDAYS.map((day, index) => (
                        <SelectItem key={day} value={String(index)}>{day}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}

              <div className="flex flex-col gap-2">
                <Label htmlFor={fieldId("hour")}>At</Label>
                <Select value={String(draft.hour)} onValueChange={(value) => change("hour", Number(value))}>
                  <SelectTrigger id={fieldId("hour")} className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {HOURS.map((hour) => (
                      <SelectItem key={hour} value={String(hour)}>{hourLabel(hour)}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>
            <p className="text-xs text-muted-foreground">
              Times are in {draft.timeZone}.
              {messageOf(errors, "time_zone") && <span className="text-destructive"> Time zone {messageOf(errors, "time_zone")}.</span>}
            </p>
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>
              {editing ? "Save Changes" : "Create check"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
