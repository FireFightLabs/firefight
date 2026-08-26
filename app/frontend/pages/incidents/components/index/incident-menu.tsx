import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconDotsVertical } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import type { Incident } from "@/pages/incidents/types"
import {
  LifecycleFormDialog,
  type LifecycleForm,
} from "@/pages/incidents/components/index/lifecycle-form-dialog"
import {
  LinkIncidentDialog,
  type LinkableIncident,
  type Relationship,
} from "@/pages/incidents/components/index/link-incident-dialog"
import { incidentReopenPath } from "@/lib/routes"
import { INCIDENT_RELATIONSHIPS } from "@/lib/generated/constants"

export function IncidentMenu({
  incident,
  linkable,
}: {
  incident: Incident
  linkable: LinkableIncident[]
}) {
  const [form, setForm] = useState<LifecycleForm | null>(null)
  const [relationship, setRelationship] = useState<Relationship | null>(null)
  // The model decides this, not a stage list kept here. An incident that can
  // no longer be changed is one that has to be reopened first.
  const terminal = Boolean(incident.changeBlockedReason)

  function openUpdate() {
    setForm("update")
  }

  function openResolve() {
    setForm("resolve")
  }

  function openCancel() {
    setForm("cancel")
  }

  function closeForm() {
    setForm(null)
  }

  function openRelated() {
    setRelationship(INCIDENT_RELATIONSHIPS.RELATED)
  }

  function openDuplicate() {
    setRelationship(INCIDENT_RELATIONSHIPS.DUPLICATE)
  }

  function closeRelationship() {
    setRelationship(null)
  }

  function reopen() {
    router.patch(incidentReopenPath(incident.id), {}, { preserveScroll: true })
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="outline"
            size="icon"
            className="size-8 border-border bg-card hover:bg-accent focus-visible:ring-0 focus-visible:ring-offset-0"
          >
            <IconDotsVertical className="size-4" />
            <span className="sr-only">Incident actions</span>
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" sideOffset={8} className="w-52">
          {terminal ? (
            <DropdownMenuItem onSelect={reopen}>Reopen incident</DropdownMenuItem>
          ) : (
            <>
              <DropdownMenuItem onSelect={openUpdate}>Post an update</DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem onSelect={openResolve}>Resolve incident</DropdownMenuItem>
              <DropdownMenuItem onSelect={openCancel}>Cancel incident</DropdownMenuItem>
            </>
          )}
          <DropdownMenuSeparator />
          {linkable.length === 0 ? (
            <Tooltip>
              <TooltipTrigger asChild>
                {/* A disabled item swallows pointer events, so the span carries the hover. */}
                <span className="block">
                  <DropdownMenuItem disabled onSelect={(event) => event.preventDefault()}>
                    Link to an incident
                  </DropdownMenuItem>
                </span>
              </TooltipTrigger>
              <TooltipContent side="left">This is the only incident in the workspace</TooltipContent>
            </Tooltip>
          ) : (
            <>
              <DropdownMenuItem onSelect={openRelated}>Link to an incident</DropdownMenuItem>
              <DropdownMenuItem onSelect={openDuplicate}>Mark as duplicate</DropdownMenuItem>
            </>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      {form && (
        <LifecycleFormDialog
          incidentId={incident.id}
          form={form}
          open
          onOpenChange={closeForm}
        />
      )}

      {relationship && (
        <LinkIncidentDialog
          incidentId={incident.id}
          relationship={relationship}
          incidents={linkable}
          open
          onOpenChange={closeRelationship}
        />
      )}
    </>
  )
}
