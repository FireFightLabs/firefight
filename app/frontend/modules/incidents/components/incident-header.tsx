import {
  IconBrandSlack,
  IconClock,
  IconDotsVertical,
  IconExternalLink,
} from "@tabler/icons-react"

import type { Incident } from "@/modules/incidents/types"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

function formatDuration(start: string, end: string | null): string {
  const s = new Date(start)
  const e = end ? new Date(end) : new Date()
  const mins = Math.floor((e.getTime() - s.getTime()) / 60000)
  if (mins < 60) return `${mins}m`
  const hours = Math.floor(mins / 60)
  const rem = mins % 60
  if (hours < 24) return `${hours}h ${rem}m`
  const days = Math.floor(hours / 24)
  return `${days}d ${hours % 24}h`
}

export function IncidentHeader({ incident }: { incident: Incident }) {
  const isActive = incident.status.lifecycleStage === "active"

  return (
    <header className="mb-8">
      <div className="flex items-center gap-2 mb-3 flex-wrap">
        {isActive && (
          <span className="relative flex size-2.5">
            <span
              className="absolute inline-flex size-full animate-ping rounded-full opacity-75"
              style={{ backgroundColor: incident.status.color }}
            />
            <span
              className="relative inline-flex size-2.5 rounded-full"
              style={{ backgroundColor: incident.status.color }}
            />
          </span>
        )}
        <Badge
          variant="secondary"
          className="gap-1 font-medium"
          style={{
            backgroundColor: `${incident.severity.color}15`,
            color: incident.severity.color,
            borderColor: `${incident.severity.color}30`,
          }}
        >
          {incident.severity.name}
        </Badge>
        <Badge
          variant="secondary"
          className="gap-1"
          style={{
            backgroundColor: `${incident.status.color}15`,
            color: incident.status.color,
            borderColor: `${incident.status.color}30`,
          }}
        >
          {incident.status.name}
        </Badge>
        {incident.type && (
          <Badge variant="outline" className="text-xs text-muted-foreground">
            {incident.type.name}
          </Badge>
        )}
        <div className="ml-auto flex items-center gap-2">
          {incident.source === "slack" && incident.channelName && (
            <Button variant="outline" size="sm" className="gap-1.5 text-muted-foreground">
              <IconBrandSlack className="size-3.5" />
              <span className="hidden sm:inline">#{incident.channelName}</span>
              <IconExternalLink className="size-3" />
            </Button>
          )}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="icon" className="size-8">
                <IconDotsVertical className="size-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem>Edit Incident</DropdownMenuItem>
              <DropdownMenuItem>Change Status</DropdownMenuItem>
              <DropdownMenuItem>Assign Lead</DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem>Close Incident</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      <h1 className="text-2xl font-bold tracking-tight mb-3">
        {incident.name}
      </h1>

      {incident.summary && (
        <p className="text-[15px] text-muted-foreground leading-relaxed mb-4 max-w-3xl">
          {incident.summary}
        </p>
      )}

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <div className="rounded-lg border bg-card/50 px-3 py-2.5">
          <span className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">Lead</span>
          <div className="mt-1 flex items-center gap-2">
            <Avatar className="size-5">
              <AvatarFallback className="text-[10px] font-medium">
                {incident.lead?.initials ?? "?"}
              </AvatarFallback>
            </Avatar>
            <span className="text-sm font-medium truncate">{incident.lead?.name ?? "Unassigned"}</span>
          </div>
        </div>
        <div className="rounded-lg border bg-card/50 px-3 py-2.5">
          <span className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">Declared</span>
          <div className="mt-1 flex items-center gap-1.5">
            <IconClock className="size-3.5 text-muted-foreground" />
            <span className="text-sm font-medium tabular-nums">
              {new Date(incident.declaredAt).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" })}
            </span>
            <span className="text-xs text-muted-foreground">
              {new Date(incident.declaredAt).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
            </span>
          </div>
        </div>
        <div className="rounded-lg border bg-card/50 px-3 py-2.5">
          <span className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">Duration</span>
          <div className="mt-1">
            <span className="text-sm font-semibold font-mono tabular-nums">
              {formatDuration(incident.declaredAt, incident.resolvedAt)}
            </span>
          </div>
        </div>
        <div className="rounded-lg border bg-card/50 px-3 py-2.5">
          <span className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">Identifier</span>
          <div className="mt-1">
            <span className="text-sm font-mono font-semibold">{incident.identifier}</span>
          </div>
        </div>
      </div>
    </header>
  )
}
