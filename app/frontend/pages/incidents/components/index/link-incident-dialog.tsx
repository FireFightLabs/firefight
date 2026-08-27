import { useState } from "react"
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
import { Label } from "@/components/ui/label"
import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { whenClosed } from "@/lib/handlers"
import { incidentLinkPath } from "@/lib/routes"
import { INCIDENT_RELATIONSHIPS } from "@/lib/generated/constants"

export type LinkableIncident = { id: string; identifier: string; name: string | null }

export type Relationship = (typeof INCIDENT_RELATIONSHIPS)[keyof typeof INCIDENT_RELATIONSHIPS]

const COPY: Record<Relationship, { title: string; description: string; label: string; confirm: string }> = {
  [INCIDENT_RELATIONSHIPS.RELATED]: {
    title: "Link to an incident",
    description: "Both incidents will name the other on their timelines. Neither one changes status.",
    label: "Related incident",
    confirm: "Link incidents",
  },
  [INCIDENT_RELATIONSHIPS.DUPLICATE]: {
    title: "Mark as duplicate",
    description: "This incident is cancelled and points at the one you pick, which stays open as the real one.",
    label: "The real incident",
    confirm: "Mark duplicate",
  },
}

function options(incidents: LinkableIncident[]): SearchableSelectOption[] {
  return incidents.map((incident) => ({
    value: incident.id,
    label: incident.name ? `${incident.identifier} — ${incident.name}` : incident.identifier,
  }))
}

export function LinkIncidentDialog({
  incidentId,
  relationship,
  incidents,
  open,
  onOpenChange,
}: {
  incidentId: string
  relationship: Relationship
  incidents: LinkableIncident[]
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const [target, setTarget] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const copy = COPY[relationship]

  function close() {
    onOpenChange(false)
  }

  function submit(event: React.FormEvent) {
    event.preventDefault()
    if (!target) {
      return
    }

    setSaving(true)
    router.post(
      incidentLinkPath(incidentId),
      { relationship, target_id: target },
      { preserveScroll: true, onSuccess: close, onFinish: () => setSaving(false) },
    )
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(close)}>
      <DialogContent onOpenAutoFocus={(event) => event.preventDefault()}>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{copy.title}</DialogTitle>
            <DialogDescription>{copy.description}</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-2 pt-3 pb-5">
            <Label>{copy.label}</Label>
            <SearchableSelect
              value={target}
              onValueChange={setTarget}
              options={options(incidents)}
              placeholder="Pick an incident"
              searchPlaceholder="Search incidents..."
              emptyText="No incidents found"
            />
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={close}>
              Never mind
            </Button>
            <Button type="submit" disabled={saving || !target}>
              {copy.confirm}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
