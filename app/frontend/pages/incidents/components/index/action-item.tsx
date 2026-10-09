import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconDotsVertical, IconExternalLink, IconKey, IconRobot, IconTicket, IconUser, type Icon } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { afterMutation } from "@/pages/incidents/lib/after-mutation"
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
import { newTabAttributes } from "@/lib/links"
import { actionStatusIcons, actionStatusLabels, actionStatusStyles } from "@/pages/incidents/lib/action-status"
import { Blocked } from "@/components/blocked-tooltip"
import { RenameItemDialog } from "@/pages/incidents/components/index/rename-item-dialog"
import {
  assignIncidentActionPath,
  completeIncidentActionPath,
  incidentItemIssuePath,
  pickUpIncidentActionPath,
  reopenIncidentItemPath,
  unassignIncidentItemPath,
} from "@/lib/routes"

// A machine holding an item wears its own mark, since who has the work is what
// a reader checks first.
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

// Taking it yourself and handing it over are separate events, so they are
// separate items rather than one picker.
function ActionMenu({
  action,
  incidentId,
  candidates,
  onRename,
}: {
  action: IncidentAction
  incidentId: string
  candidates: InlineChoice[]
  onRename: () => void
}) {
  const isDone = action.status === "done"

  function pickUp() {
    router.patch(pickUpIncidentActionPath(incidentId, action.id), {}, afterMutation("actions", "timelineEvents"))
  }

  function complete() {
    router.patch(completeIncidentActionPath(incidentId, action.id), {}, afterMutation("actions", "timelineEvents"))
  }

  function assign(memberId: string) {
    router.patch(assignIncidentActionPath(incidentId, action.id), { member_id: memberId }, afterMutation("actions", "timelineEvents"))
  }

  function reopen() {
    router.patch(reopenIncidentItemPath(incidentId, action.id), {}, afterMutation("actions", "timelineEvents"))
  }

  function unassign() {
    router.patch(unassignIncidentItemPath(incidentId, action.id), {}, afterMutation("actions", "timelineEvents"))
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="size-6 shrink-0 text-fg-muted hover:text-fg-primary"
        >
          <IconDotsVertical className="size-3.5" />
          <span className="sr-only">Item actions</span>
        </Button>
      </DropdownMenuTrigger>
      {isDone ? (
        <DropdownMenuContent align="end" className="w-52">
          <DropdownMenuItem onSelect={reopen}>Reopen</DropdownMenuItem>
          <DropdownMenuItem onSelect={onRename}>Rename</DropdownMenuItem>
        </DropdownMenuContent>
      ) : (
        <DropdownMenuContent align="end" className="max-h-72 w-52 overflow-y-auto">
          {!action.assignee && <DropdownMenuItem onSelect={pickUp}>Pick up</DropdownMenuItem>}
          <DropdownMenuItem onSelect={complete}>Mark done</DropdownMenuItem>
          <DropdownMenuItem onSelect={onRename}>Rename</DropdownMenuItem>
          {action.assignee && <DropdownMenuItem onSelect={unassign}>Unassign</DropdownMenuItem>}
          <DropdownMenuSeparator />
          <DropdownMenuLabel className="text-xs font-normal text-muted-foreground">Assign to</DropdownMenuLabel>
          {candidates.map((candidate) => (
            <DropdownMenuItem key={candidate.value} onSelect={() => assign(candidate.value)}>
              {candidate.label}
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      )}
    </DropdownMenu>
  )
}

// Opens the item's issue in the workspace's tracker, or tries again after it failed. The issue arrives in a job, so
// the page shows that it is being opened until it is there.
function IssueRequest({ action, incidentId }: { action: IncidentAction; incidentId: string }) {
  const blockedReason = action.issueRequestBlockedReason ?? undefined

  function createIssue() {
    router.post(incidentItemIssuePath(incidentId, action.id), {}, afterMutation("actions"))
  }

  return (
    <Blocked reason={blockedReason} side="top">
      <button
        type="button"
        onClick={createIssue}
        disabled={Boolean(blockedReason)}
        className="inline-flex items-center gap-1 hover:text-fg-primary hover:underline disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:no-underline"
      >
        <IconTicket className="size-3 shrink-0" />
        {action.issueMissing ? "Try the issue again" : "Create issue"}
      </button>
    </Blocked>
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
  const [renaming, setRenaming] = useState(false)

  function startRenaming() {
    setRenaming(true)
  }

  return (
    <div id={actionAnchorId(action.id)} className="group py-3 border-b border-border last:border-b-0 transition-shadow">
      <div className="flex items-start gap-3">
        <div className={`mt-0.5 shrink-0 ${statusColor}`}>
          <StatusIcon className="block size-[15px]" strokeWidth={1.75} />
        </div>
        <p className={`flex-1 text-[13px] leading-[1.5] ${isDone ? "line-through text-fg-muted" : "text-fg-primary"}`}>
          {action.description}
        </p>
        {canEdit && (
          <span className="opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
            <ActionMenu action={action} incidentId={incidentId} candidates={candidates} onRename={startRenaming} />
          </span>
        )}
      </div>
      <div className="mt-1 flex items-center gap-1.5 pl-[27px] text-xs text-fg-muted">
        {action.assignee ? (
          <AssigneeMark assignee={action.assignee} />
        ) : (
          <span className="italic text-fg-muted">Unassigned</span>
        )}
        <span className="text-fg-disabled">·</span>
        <span className={statusColor}>{actionStatusLabels[action.status]}</span>
        {action.externalUrl && (
          <>
            <span className="text-fg-disabled">·</span>
            <a
              href={action.externalUrl}
              {...newTabAttributes(action.externalUrl)}
              className="inline-flex min-w-0 items-center gap-1 hover:text-fg-primary hover:underline"
            >
              <span className="truncate">{action.externalKey ?? "Open issue"}</span>
              <IconExternalLink className="size-3 shrink-0" />
            </a>
          </>
        )}
        {canEdit && action.issueRequestOffered && (
          <>
            <span className="text-fg-disabled">·</span>
            <IssueRequest action={action} incidentId={incidentId} />
          </>
        )}
      </div>
      {action.issueStatus && <p className="mt-1 pl-[27px] text-xs text-fg-muted">{action.issueStatus}</p>}
      {canEdit && renaming && (
        <RenameItemDialog action={action} incidentId={incidentId} open={renaming} onOpenChange={setRenaming} />
      )}
    </div>
  )
}
