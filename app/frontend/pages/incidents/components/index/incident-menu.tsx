import { useState } from "react"
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
} from "@/components/incidents/lifecycle-form-dialog"
import {
  LinkIncidentDialog,
  type LinkableIncident,
  type Relationship,
} from "@/pages/incidents/components/index/link-incident-dialog"
import { EscalateDialog } from "@/pages/incidents/components/index/escalate-dialog"
import { InviteDialog } from "@/pages/incidents/components/index/invite-dialog"
import { ShoutoutDialog } from "@/pages/incidents/components/index/shoutout-dialog"
import { ReopenDialog } from "@/pages/incidents/components/index/reopen-dialog"
import { UPDATE_VISIT } from "@/pages/incidents/lib/after-mutation"
import { INCIDENT_RELATIONSHIPS } from "@/lib/generated/constants"

// Only one is ever open, so one piece of state rather than three that could
// contradict each other.
type OpenDialog =
  | { kind: "lifecycle"; form: LifecycleForm }
  | { kind: "link"; relationship: Relationship }
  | { kind: "escalate" }
  | { kind: "invite" }
  | { kind: "shoutout" }
  | { kind: "reopen" }

const UPDATE: OpenDialog = { kind: "lifecycle", form: "update" }
const RESOLVE: OpenDialog = { kind: "lifecycle", form: "resolve" }
const CANCEL: OpenDialog = { kind: "lifecycle", form: "cancel" }
const RELATED: OpenDialog = { kind: "link", relationship: INCIDENT_RELATIONSHIPS.RELATED }
const DUPLICATE: OpenDialog = { kind: "link", relationship: INCIDENT_RELATIONSHIPS.DUPLICATE }
const ESCALATE: OpenDialog = { kind: "escalate" }
const INVITE: OpenDialog = { kind: "invite" }
const SHOUTOUT: OpenDialog = { kind: "shoutout" }
const REOPEN: OpenDialog = { kind: "reopen" }

// A control the model refused stays visible and says why, instead of vanishing.
function MenuItem({
  label,
  dialog,
  blockedReason,
  onOpen,
}: {
  label: string
  dialog: OpenDialog
  blockedReason?: string
  onOpen: (dialog: OpenDialog) => void
}) {
  function open() {
    onOpen(dialog)
  }

  if (!blockedReason) {
    return <DropdownMenuItem onSelect={open}>{label}</DropdownMenuItem>
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
  const [dialog, setDialog] = useState<OpenDialog | null>(null)
  // The model decides this. An incident that can no longer be changed has to
  // be reopened first.
  const terminal = Boolean(incident.changeBlockedReason)

  function close() {
    setDialog(null)
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="outline"
            size="icon"
            className="size-8 border-border bg-card hover:bg-accent"
          >
            <IconDotsVertical className="size-4" />
            <span className="sr-only">Incident actions</span>
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" sideOffset={8} className="w-56">
          {terminal ? (
            <MenuItem label="Reopen incident" dialog={REOPEN} onOpen={setDialog} />
          ) : (
            <>
              <MenuItem label="Post an update" dialog={UPDATE} onOpen={setDialog} />
              <DropdownMenuSeparator />
              <MenuItem
                label="Ask someone to pick this up"
                dialog={ESCALATE}
                blockedReason={incident.escalationBlockedReason}
                onOpen={setDialog}
              />
              <MenuItem
                label="Bring people in"
                dialog={INVITE}
                blockedReason={incident.inviteBlockedReason}
                onOpen={setDialog}
              />
              <MenuItem
                label="Give a shoutout"
                dialog={SHOUTOUT}
                blockedReason={incident.shoutoutBlockedReason}
                onOpen={setDialog}
              />
              <DropdownMenuSeparator />
              <MenuItem label="Resolve incident" dialog={RESOLVE} onOpen={setDialog} />
              <MenuItem label="Cancel incident" dialog={CANCEL} onOpen={setDialog} />
            </>
          )}
          <DropdownMenuSeparator />
          <MenuItem
            label="Link to an incident"
            dialog={RELATED}
            blockedReason={linkable.length === 0 ? "This is the only incident in the workspace" : undefined}
            onOpen={setDialog}
          />
          {linkable.length > 0 && (
            <MenuItem label="Mark as duplicate" dialog={DUPLICATE} onOpen={setDialog} />
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      {dialog?.kind === "lifecycle" && (
        <LifecycleFormDialog incidentId={incident.id} form={dialog.form} open onOpenChange={close} updateVisit={UPDATE_VISIT} />
      )}

      {dialog?.kind === "link" && (
        <LinkIncidentDialog
          incidentId={incident.id}
          relationship={dialog.relationship}
          incidents={linkable}
          open
          onOpenChange={close}
        />
      )}

      {dialog?.kind === "escalate" && (
        <EscalateDialog incidentId={incident.id} members={members} open onOpenChange={close} />
      )}

      {dialog?.kind === "invite" && (
        <InviteDialog incidentId={incident.id} members={members} open onOpenChange={close} />
      )}

      {dialog?.kind === "reopen" && <ReopenDialog incidentId={incident.id} open onOpenChange={close} />}

      {dialog?.kind === "shoutout" && (
        <ShoutoutDialog incidentId={incident.id} members={members} open onOpenChange={close} />
      )}
    </>
  )
}
