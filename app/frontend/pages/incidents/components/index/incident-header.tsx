import {
  IconBrandSlack,
  IconDotsVertical,
  IconExternalLink,
} from "@tabler/icons-react"

import type { Incident } from "@/pages/incidents/types"
import { severityBadgeStyle } from "@/lib/severity-color"
import { formatDuration } from "@/lib/formatters"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { MetaCell } from "@/pages/incidents/components/index/meta-cell"
import { StatusIcon } from "@/pages/dashboard/components/status-icon"

export function IncidentHeader({ incident }: { incident: Incident }) {
  const declared = new Date(incident.declaredAt)

  return (
    <header className="mb-10">
      <div className="flex items-start justify-between gap-4 mb-6">
        <div className="flex items-center gap-2 flex-wrap min-w-0">
          <Badge className="min-w-24 justify-center py-1" style={severityBadgeStyle(incident.severity.color)}>
            {incident.severity.name}
          </Badge>
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
          {incident.type && (
            <span className="inline-flex items-center rounded-full border border-border bg-transparent px-2.5 py-1 text-[11px] font-medium text-muted-foreground">
              {incident.type.name}
            </span>
          )}
        </div>
        <div className="flex items-center gap-2 shrink-0">
          {incident.source === "slack" && incident.channelName && incident.channelId && (
            <Button
              variant="outline"
              size="sm"
              className="h-8 gap-2 border-primary/30 bg-primary/10 px-3 font-mono text-[12px] text-primary hover:bg-primary/20 hover:border-primary/50 hover:text-primary"
              asChild
            >
              <a
                href={`https://slack.com/app_redirect?channel=${incident.channelId}`}
                target="_blank"
                rel="noopener noreferrer"
              >
                <IconBrandSlack className="size-3.5" />
                <span className="hidden sm:inline">#{incident.channelName}</span>
                <IconExternalLink className="size-3 opacity-50" />
              </a>
            </Button>
          )}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="outline"
                size="icon"
                className="size-8 border-border bg-card hover:bg-accent focus-visible:ring-0 focus-visible:ring-offset-0"
              >
                <IconDotsVertical className="size-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" sideOffset={8}>
              <DropdownMenuItem>Close Incident</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
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

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-x-8 gap-y-4">
        <MetaCell label="Lead">
          {incident.lead ? (
            <div className="flex items-center gap-2">
              <Avatar className="size-5">
                {incident.lead.avatarUrl ? (
                  <AvatarImage src={incident.lead.avatarUrl} alt={incident.lead.name} />
                ) : null}
                <AvatarFallback className="text-[10px] font-semibold bg-primary/20 text-primary">
                  {incident.lead.initials}
                </AvatarFallback>
              </Avatar>
              <span className="font-medium truncate">{incident.lead.name}</span>
            </div>
          ) : (
            <span className="text-muted-foreground">Unassigned</span>
          )}
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
                  {key.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase())}
                </span>
                <span className="text-foreground truncate">
                  {Array.isArray(value) ? value.join(", ") : String(value ?? "")}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </header>
  )
}
