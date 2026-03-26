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
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
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
  open: "text-muted-foreground",
  in_progress: "text-amber-500",
  done: "text-emerald-500",
}

function ProgressBar({ done, total }: { done: number; total: number }) {
  const pct = total > 0 ? (done / total) * 100 : 0
  return (
    <div className="flex items-center gap-2">
      <div className="h-1.5 flex-1 rounded-full bg-muted overflow-hidden">
        <div
          className="h-full rounded-full bg-emerald-500 transition-all duration-500"
          style={{ width: `${pct}%` }}
        />
      </div>
      <span className="text-[11px] font-mono tabular-nums text-muted-foreground">
        {done}/{total}
      </span>
    </div>
  )
}

function ActionItem({ action }: { action: IncidentAction }) {
  const StatusIcon = statusIcons[action.status]
  const statusColor = statusStyles[action.status]
  const isDone = action.status === "done"

  return (
    <div className="group flex items-start gap-3 rounded-md px-3 py-3 transition-colors hover:bg-muted/40 -mx-3">
      <div className={`mt-0.5 ${statusColor}`}>
        <StatusIcon className="size-[18px]" />
      </div>
      <div className="flex-1 min-w-0">
        <p className={`text-sm leading-snug ${isDone ? "line-through text-muted-foreground" : ""}`}>
          {action.description}
        </p>
        {action.assignee ? (
          <span className="mt-1 inline-flex items-center gap-1 text-xs text-muted-foreground">
            <IconUser className="size-3" />
            {action.assignee}
          </span>
        ) : (
          <span className="mt-1 inline-flex items-center gap-1 text-xs text-muted-foreground/50 italic">
            Unassigned
          </span>
        )}
      </div>
      <Badge
        variant="outline"
        className={`text-[11px] capitalize shrink-0 ${statusColor} opacity-80`}
      >
        {action.status.replace("_", " ")}
      </Badge>
    </div>
  )
}

function AddActionDialog() {
  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button variant="ghost" size="icon" className="size-7 text-muted-foreground">
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

function ActionCard({
  title,
  icon: Icon,
  items,
}: {
  title: string
  icon: typeof IconCheckbox
  items: IncidentAction[]
}) {
  const doneCount = items.filter((a) => a.status === "done").length

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Icon className="size-4 text-muted-foreground" />
            <CardTitle className="text-sm">{title}</CardTitle>
          </div>
          <AddActionDialog />
        </div>
        <div className="mt-2">
          <ProgressBar done={doneCount} total={items.length} />
        </div>
      </CardHeader>
      <CardContent className="pt-0">
        {items.map((action) => (
          <ActionItem key={action.id} action={action} />
        ))}
      </CardContent>
    </Card>
  )
}

export function IncidentActionsSidebar({ actions }: { actions: IncidentAction[] }) {
  const actionItems = actions.filter((a) => a.actionType === "action")
  const followups = actions.filter((a) => a.actionType === "followup")

  return (
    <div className="flex flex-col gap-4">
      <ActionCard title="Actions" icon={IconCheckbox} items={actionItems} />
      <ActionCard title="Follow-ups" icon={IconChecks} items={followups} />
    </div>
  )
}
