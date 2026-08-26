import { router } from "@inertiajs/react"
import { IconDotsVertical, IconKey, IconRobot, IconUser, type Icon } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import type { ActorCompact } from "@/types/serializers"
import type { IncidentAction } from "@/pages/incidents/types"
import type { InlineChoice } from "@/pages/incidents/components/index/inline-select"
import { PRINCIPAL_KINDS } from "@/lib/generated/constants"
import { actionAnchorId } from "@/pages/incidents/lib/action-anchor"
import { actionStatusIcons, actionStatusLabels, actionStatusStyles } from "@/pages/incidents/lib/action-status"
import {
  assignIncidentActionPath,
  completeIncidentActionPath,
  pickUpIncidentActionPath,
} from "@/lib/routes"

// A machine holding an item wears its own mark, since who has the work is the
// first thing a reader checks.
const KIND_ICONS: Partial<Record<ActorCompact["kind"], Icon>> = {
  [PRINCIPAL_KINDS.AGENT]: IconRobot,
  [PRINCIPAL_KINDS.API_KEY]: IconKey,
}

function AssigneeMark({ assignee }: { assignee: ActorCompact }) {
  const KindIcon = KIND_ICONS[assignee.kind] ?? IconUser

  return (
    <span className="inline-flex items-center gap-1.5">
      {assignee.avatarUrl ? (
        <img src={assignee.avatarUrl} alt="" className="size-3.5 rounded-full object-cover" />
      ) : (
        <KindIcon className="size-3" />
      )}
      {assignee.name}
    </span>
  )
}

// Taking it yourself and handing it over are separate events, which is why
// they are separate items rather than one picker that happens to include you.
function ActionMenu({
  action,
  incidentId,
  candidates,
}: {
  action: IncidentAction
  incidentId: string
  candidates: InlineChoice[]
}) {
  function pickUp() {
    router.patch(pickUpIncidentActionPath(incidentId, action.id), {}, { preserveScroll: true })
  }

  function complete() {
    router.patch(completeIncidentActionPath(incidentId, action.id), {}, { preserveScroll: true })
  }

  function assign(memberId: string) {
    router.patch(assignIncidentActionPath(incidentId, action.id), { member_id: memberId }, { preserveScroll: true })
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="size-6 shrink-0 text-muted-foreground/50 hover:text-foreground"
        >
          <IconDotsVertical className="size-3.5" />
          <span className="sr-only">Item actions</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="max-h-72 w-52 overflow-y-auto">
        {!action.assignee && <DropdownMenuItem onSelect={pickUp}>Pick up</DropdownMenuItem>}
        <DropdownMenuItem onSelect={complete}>Mark done</DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuLabel className="text-xs font-normal text-muted-foreground">Assign to</DropdownMenuLabel>
        {candidates.map((candidate) => (
          <DropdownMenuItem key={candidate.value} onSelect={() => assign(candidate.value)}>
            {candidate.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

export function ActionItem({
  action,
  incidentId,
  candidates,
  canEdit,
}: {
  action: IncidentAction
  incidentId: string
  candidates: InlineChoice[]
  canEdit: boolean
}) {
  const StatusIcon = actionStatusIcons[action.status]
  const statusColor = actionStatusStyles[action.status]
  const isDone = action.status === "done"

  return (
    <div id={actionAnchorId(action.id)} className="group py-3 border-b border-border/60 last:border-b-0 transition-shadow">
      <div className="flex items-start gap-3">
        <div className={`mt-0.5 shrink-0 ${statusColor}`}>
          <StatusIcon className="block size-[15px]" strokeWidth={1.75} />
        </div>
        <p className={`flex-1 text-[13px] leading-[1.5] ${isDone ? "line-through text-muted-foreground/60" : "text-foreground"}`}>
          {action.description}
        </p>
        {canEdit && !isDone && (
          <span className="opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
            <ActionMenu action={action} incidentId={incidentId} candidates={candidates} />
          </span>
        )}
      </div>
      <div className="mt-1 flex items-center gap-1.5 pl-[27px] text-xs text-muted-foreground/60">
        {action.assignee ? (
          <AssigneeMark assignee={action.assignee} />
        ) : (
          <span className="italic text-muted-foreground/40">Unassigned</span>
        )}
        <span className="text-muted-foreground/50">·</span>
        <span className={statusColor}>{actionStatusLabels[action.status]}</span>
      </div>
    </div>
  )
}
