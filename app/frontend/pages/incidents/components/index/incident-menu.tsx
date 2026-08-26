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
import type { SearchableSelectOption } from "@/components/searchable-select"
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
import { EscalateDialog } from "@/pages/incidents/components/index/escalate-dialog"
import { InviteDialog } from "@/pages/incidents/components/index/invite-dialog"
import { ShoutoutDialog } from "@/pages/incidents/components/index/shoutout-dialog"
import { incidentReopenPath } from "@/lib/routes"
import { INCIDENT_RELATIONSHIPS } from "@/lib/generated/constants"

type Participation = "escalate" | "invite" | "shoutout"

// A control the model has refused stays visible and says why, rather than
// vanishing and leaving the reader to guess.
function MenuItem({
  label,
  blockedReason,
  onSelect,
}: {
  label: string
  blockedReason?: string
  onSelect: () => void
}) {
  if (!blockedReason) {
    return <DropdownMenuItem onSelect={onSelect}>{label}</DropdownMenuItem>
  }

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        {/* A disabled item swallows pointer events, so the span carries the hover. */}
        <span className="block">
          <DropdownMenuItem disabled onSelect={(event) => event.preventDefault()}>
            {label}
          </DropdownMenuItem>
        </span>
      </TooltipTrigger>
      <TooltipContent side="left">{blockedReason}</TooltipContent>
    </Tooltip>
  )
}

export function IncidentMenu({
  incident,
  linkable,
  members,
}: {
  incident: Incident
  linkable: LinkableIncident[]
  members: SearchableSelectOption[]
}) {
  const [form, setForm] = useState<LifecycleForm | null>(null)
  const [relationship, setRelationship] = useState<Relationship | null>(null)
  const [participation, setParticipation] = useState<Participation | null>(null)
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

  function openEscalate() {
    setParticipation("escalate")
  }

  function openInvite() {
    setParticipation("invite")
  }

  function openShoutout() {
    setParticipation("shoutout")
  }

  function closeParticipation() {
    setParticipation(null)
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
        <DropdownMenuContent align="end" sideOffset={8} className="w-56">
          {terminal ? (
            <DropdownMenuItem onSelect={reopen}>Reopen incident</DropdownMenuItem>
          ) : (
            <>
              <DropdownMenuItem onSelect={openUpdate}>Post an update</DropdownMenuItem>
              <DropdownMenuSeparator />
              <MenuItem
                label="Ask someone to pick this up"
                blockedReason={incident.escalationBlockedReason}
                onSelect={openEscalate}
              />
              <MenuItem
                label="Bring people in"
                blockedReason={incident.inviteBlockedReason}
                onSelect={openInvite}
              />
              <MenuItem
                label="Give a shoutout"
                blockedReason={incident.shoutoutBlockedReason}
                onSelect={openShoutout}
              />
              <DropdownMenuSeparator />
              <DropdownMenuItem onSelect={openResolve}>Resolve incident</DropdownMenuItem>
              <DropdownMenuItem onSelect={openCancel}>Cancel incident</DropdownMenuItem>
            </>
          )}
          <DropdownMenuSeparator />
          {linkable.length === 0 ? (
            <MenuItem
              label="Link to an incident"
              blockedReason="This is the only incident in the workspace"
              onSelect={openRelated}
            />
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

      {participation === "escalate" && (
        <EscalateDialog incidentId={incident.id} members={members} open onOpenChange={closeParticipation} />
      )}

      {participation === "invite" && (
        <InviteDialog incidentId={incident.id} members={members} open onOpenChange={closeParticipation} />
      )}

      {participation === "shoutout" && (
        <ShoutoutDialog incidentId={incident.id} members={members} open onOpenChange={closeParticipation} />
      )}
    </>
  )
}
