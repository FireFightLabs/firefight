import {
  IconCheckbox,
  IconChecks,
  IconCircleCheck,
  IconCircleDashed,
  IconLoader,
  IconPlus,
  IconUser,
} from "@tabler/icons-react"

import type { IncidentAction } from "@/modules/incidents/types"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"

const statusIcons: Record<string, typeof IconCircleDashed> = {
  open: IconCircleDashed,
  in_progress: IconLoader,
  done: IconCircleCheck,
}

const statusStyles: Record<string, string> = {
  open: "text-muted-foreground/70",
  in_progress: "text-amber-400",
  done: "text-emerald-400",
}

const statusLabels: Record<string, string> = {
  open: "Open",
  in_progress: "In progress",
  done: "Done",
}

function ProgressRail({ done, total }: { done: number; total: number }) {
  const pct = total > 0 ? (done / total) * 100 : 0
  const complete = total > 0 && done === total
  return (
    <div className="flex items-center gap-3">
      <div className="h-1 flex-1 rounded-full bg-muted overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-700 ease-out ${complete ? "bg-emerald-400" : "bg-primary"}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <span className="font-mono text-[11px] tabular-nums text-muted-foreground">
        {done}
        <span className="text-muted-foreground/50">/</span>
        {total}
      </span>
    </div>
  )
}

function ActionItem({ action }: { action: IncidentAction }) {
  const StatusIcon = statusIcons[action.status]
  const statusColor = statusStyles[action.status]
  const isDone = action.status === "done"

  return (
    <div className="group flex items-start gap-3 py-2.5 first:pt-0 last:pb-0 border-b border-border last:border-b-0">
      <div className={`mt-0.5 shrink-0 ${statusColor}`}>
        <StatusIcon className="size-[17px]" strokeWidth={1.75} />
      </div>
      <div className="flex-1 min-w-0">
        <p className={`text-[13px] leading-[1.5] ${isDone ? "line-through text-muted-foreground/70" : "text-foreground"}`}>
          {action.description}
        </p>
        <div className="mt-1 flex items-center gap-2 text-[11px] text-muted-foreground/80">
          {action.assignee ? (
            <span className="inline-flex items-center gap-1">
              <IconUser className="size-3" />
              {action.assignee}
            </span>
          ) : (
            <span className="italic text-muted-foreground/50">Unassigned</span>
          )}
          <span className="size-1 rounded-full bg-muted-foreground/30" />
          <span className={statusColor}>{statusLabels[action.status]}</span>
        </div>
      </div>
    </div>
  )
}

function AddActionDialog() {
  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="size-7 text-muted-foreground/70 hover:text-foreground hover:bg-muted/50"
          aria-label="Add action item"
        >
          <IconPlus className="size-3.5" />
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add Action Item</DialogTitle>
          <DialogDescription>Create a new action item for this incident.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-4 py-2">
          <div className="flex flex-col gap-2">
            <Label htmlFor="action-desc">Description</Label>
            <Textarea id="action-desc" placeholder="What needs to be done?" rows={2} />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="action-assignee">Assignee</Label>
            <Input id="action-assignee" placeholder="e.g. Sarah Chen" />
          </div>
        </div>
        <DialogFooter>
          <DialogClose asChild><Button variant="outline">Cancel</Button></DialogClose>
          <Button>Create</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function ActionPanel({
  title,
  icon: Icon,
  items,
}: {
  title: string
  icon: typeof IconCheckbox
  items: IncidentAction[]
}) {
  const doneCount = items.filter((a) => a.status === "done").length
  const isEmpty = items.length === 0

  return (
    <section className="rounded-xl border border-border bg-card overflow-hidden">
      <header className="flex items-center justify-between px-4 pt-3.5 pb-2.5">
        <div className="flex items-center gap-2">
          <Icon className="size-3.5 text-muted-foreground" strokeWidth={1.75} />
          <h3 className="text-[12px] font-semibold uppercase tracking-[0.12em] text-foreground">
            {title}
          </h3>
        </div>
        <AddActionDialog />
      </header>
      <div className="px-4 pb-2">
        <ProgressRail done={doneCount} total={items.length} />
      </div>
      {!isEmpty && (
        <div className="px-4 pt-2 pb-3">
          {items.map((action) => (
            <ActionItem key={action.id} action={action} />
          ))}
        </div>
      )}
      {isEmpty && (
        <div className="px-4 pb-4 text-[12px] text-muted-foreground/70">
          None yet.
        </div>
      )}
    </section>
  )
}

export function IncidentActionsSidebar({ actions }: { actions: IncidentAction[] }) {
  const actionItems = actions.filter((a) => a.actionType === "action")
  const followups = actions.filter((a) => a.actionType === "followup")

  return (
    <div className="flex flex-col gap-3">
      <ActionPanel title="Actions" icon={IconCheckbox} items={actionItems} />
      <ActionPanel title="Follow-ups" icon={IconChecks} items={followups} />
    </div>
  )
}
