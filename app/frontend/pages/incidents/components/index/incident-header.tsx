import { useState } from "react"
import {
  IconBrandSlack,
  IconExternalLink,
} from "@tabler/icons-react"

import type { Incident } from "@/pages/incidents/types"
import { severityBadgeStyle } from "@/lib/severity-color"
import { formatDuration } from "@/lib/formatters"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { MetaCell } from "@/pages/incidents/components/index/meta-cell"
import { PersonChip } from "@/pages/incidents/components/index/person-chip"
import { IncidentMenu } from "@/pages/incidents/components/index/incident-menu"
import { InlineSelect } from "@/pages/incidents/components/index/inline-select"
import { LifecycleFormDialog } from "@/pages/incidents/components/index/lifecycle-form-dialog"
import type { LinkableIncident } from "@/pages/incidents/components/index/link-incident-dialog"
import { StatusIcon } from "@/pages/dashboard/components/status-icon"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { assignIncidentRolePath } from "@/lib/routes"
import { LEAD_ROLE_SLUG } from "@/lib/generated/constants"

// The badge itself is the affordance. A responder clicking it is asking to
// change the incident, and the workspace's Update form is what asks how. Once
// the incident is over the badge stays put and says why it no longer opens.
function EditableBadge({
  blockedReason,
  onEdit,
  label,
  children,
}: {
  blockedReason?: string | null
  onEdit: () => void
  label: string
  children: React.ReactNode
}) {
  if (blockedReason) {
    return (
      <Tooltip>
        <TooltipTrigger asChild>
          <span className="cursor-default opacity-70">{children}</span>
        </TooltipTrigger>
        <TooltipContent className="max-w-64">{blockedReason}</TooltipContent>
      </Tooltip>
    )
  }

  return (
    <button
      type="button"
      onClick={onEdit}
      aria-label={label}
      title={label}
      className="rounded-full transition-opacity hover:opacity-80 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
    >
      {children}
    </button>
  )
}

export function IncidentHeader({
  incident,
  channelUrl,
  linkable,
  canEdit,
  leadCandidates,
}: {
  incident: Incident
  channelUrl?: string | null
  linkable: LinkableIncident[]
  canEdit: boolean
  leadCandidates: { value: string; label: string }[]
}) {
  const declared = new Date(incident.declaredAt)
  // Severity and status are questions on the workspace's Update form, and
  // Slack asks the whole form for either. So the badges open that form rather
  // than writing one field on their own, which would skip whatever else the
  // workspace requires. The lead has its own dedicated modal in Slack, so it
  // gets a dropdown here for the same reason.
  const [updating, setUpdating] = useState(false)
  // The model owns why an incident can no longer be changed. Working it out
  // from the lifecycle stage here would be the same rule written twice.
  const blockedReason = canEdit ? incident.changeBlockedReason : "You do not have permission to change incidents."

  function openUpdate() {
    setUpdating(true)
  }

  function closeUpdate() {
    setUpdating(false)
  }

  function leadPayload(memberId: string) {
    return { role: LEAD_ROLE_SLUG, member_id: memberId }
  }

  return (
    <header className="mb-10">
      <div className="flex items-start justify-between gap-4 mb-6">
        <div className="flex items-center gap-2 flex-wrap min-w-0">
          <EditableBadge blockedReason={blockedReason} onEdit={openUpdate} label="Change severity">
            <Badge className="min-w-24 justify-center py-1" style={severityBadgeStyle(incident.severity.color)}>
              {incident.severity.name}
            </Badge>
          </EditableBadge>
          <EditableBadge blockedReason={blockedReason} onEdit={openUpdate} label="Change status">
            <Badge
              style={{
                backgroundColor: `${incident.status.color}33`,
                color: incident.status.color,
                borderColor: `${incident.status.color}66`,
                minWidth: "7.5rem",
                paddingTop: "0.25rem",
                paddingBottom: "0.25rem",
              }}
            >
              <StatusIcon statusName={incident.status.name} lifecycleStage={incident.status.lifecycleStage} />
              {incident.status.name}
            </Badge>
          </EditableBadge>
          {incident.type && (
            <span className="inline-flex items-center rounded-full border border-border bg-transparent px-2.5 py-1 text-[11px] font-medium text-muted-foreground">
              {incident.type.name}
            </span>
          )}
        </div>
        <div className="flex items-center gap-2 shrink-0">
          {channelUrl && incident.channelName && (
            <Button
              variant="outline"
              size="sm"
              className="h-8 gap-2 border-primary/30 bg-primary/10 px-3 font-mono text-[12px] text-primary hover:bg-primary/20 hover:border-primary/50 hover:text-primary"
              asChild
            >
              <a href={channelUrl} target="_blank" rel="noopener noreferrer">
                <IconBrandSlack className="size-3.5" />
                <span className="hidden sm:inline">#{incident.channelName}</span>
                <IconExternalLink className="size-3 opacity-50" />
              </a>
            </Button>
          )}
          {canEdit && <IncidentMenu incident={incident} linkable={linkable} />}
        </div>
      </div>

      <h1 className="text-[28px] leading-[1.15] font-semibold tracking-[-0.02em] text-foreground mb-4">
        {incident.name}
      </h1>

      {incident.summary && (
        <p className="text-[15px] leading-[1.65] text-muted-foreground max-w-[65ch] mb-8">
          {incident.summary}
        </p>
      )}

      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-x-8 gap-y-4">
        <MetaCell label="Lead">
          <InlineSelect
            trigger={<PersonChip person={incident.lead} fallback="Unassigned" />}
            choices={leadCandidates}
            selected={incident.leadId ?? null}
            path={assignIncidentRolePath(incident.id)}
            payload={leadPayload}
            blockedReason={blockedReason}
          />
        </MetaCell>
        <MetaCell label="Declared by">
          <PersonChip person={incident.declaredBy} fallback="-" />
        </MetaCell>
        <MetaCell label="Declared">
          <div className="flex items-baseline gap-1.5">
            <span className="font-mono tabular-nums text-[13px]">
              {declared.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false })}
            </span>
            <span className="text-muted-foreground text-[12px]">
              {declared.toLocaleDateString("en-US", { month: "short", day: "numeric" })}
            </span>
          </div>
        </MetaCell>
        <MetaCell label="Duration">
          <span className="font-mono tabular-nums font-medium">
            {formatDuration(incident.declaredAt, incident.resolvedAt)}
          </span>
        </MetaCell>
        <MetaCell label="Source">
          <span className="capitalize">{incident.source}</span>
        </MetaCell>
      </div>

      {incident.customFields && Object.keys(incident.customFields).length > 0 && (
        <div className="mt-4 rounded-xl border border-border bg-card px-5 py-4">
          <div className="text-[10px] font-medium uppercase tracking-[0.18em] text-muted-foreground/70 mb-3">
            Custom Fields
          </div>
          <div className="grid gap-x-8 gap-y-2 sm:grid-cols-2">
            {Object.entries(incident.customFields).map(([key, value]) => (
              <div key={key} className="flex items-baseline gap-3 text-sm min-w-0">
                <span className="text-xs text-muted-foreground shrink-0">
                  {key.replace(/_/g, " ").replace(/\b\w/g, (char) => char.toUpperCase())}
                </span>
                <span className="text-foreground truncate">
                  {Array.isArray(value) ? value.join(", ") : String(value ?? "")}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
      <LifecycleFormDialog
        incidentId={incident.id}
        form="update"
        open={updating}
        onOpenChange={closeUpdate}
      />
    </header>
  )
}
