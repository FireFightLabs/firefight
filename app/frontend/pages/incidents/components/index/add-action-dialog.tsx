import { useState } from "react"
import { useForm } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

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
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { useMemberSearch } from "@/hooks/use-member-search"

function memberOptions(members: { id: string; name: string; avatarUrl?: string }[]): SearchableSelectOption[] {
  const unassigned: SearchableSelectOption = { value: "", label: "Unassigned" }
  const options = members.map((m) => ({
    value: m.id,
    label: m.name,
    icon: m.avatarUrl
      ? <img src={m.avatarUrl} alt="" className="size-5 rounded-full" />
      : <div className="size-5 rounded-full bg-muted" />,
  }))
  return [unassigned, ...options]
}

export function AddActionDialog({
  disabled = false,
  incidentId,
  actionType,
  disabledTooltip = "Not available",
}: {
  disabled?: boolean
  incidentId: string
  actionType: "action" | "followup"
  disabledTooltip?: string
}) {
  const [open, setOpen] = useState(false)
  const { members, loadMembers } = useMemberSearch()
  const { data, setData, post, processing, reset } = useForm({
    description: "",
    action_type: actionType,
    assignee_id: "",
  })

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    post(`/app/incidents/${incidentId}/actions`, {
      onSuccess: () => {
        setOpen(false)
        reset()
      },
    })
  }

  const trigger = (
    <Button
      variant="ghost"
      size="icon"
      className="size-7 text-muted-foreground/70 hover:text-foreground hover:bg-muted/50 disabled:opacity-40 disabled:pointer-events-none"
      aria-label="Add action item"
      disabled={disabled}
    >
      <IconPlus className="size-3.5" />
    </Button>
  )

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      {disabled ? (
        <Tooltip>
          <TooltipTrigger asChild>
            <span>{trigger}</span>
          </TooltipTrigger>
          <TooltipContent>{disabledTooltip}</TooltipContent>
        </Tooltip>
      ) : (
        <DialogTrigger asChild>{trigger}</DialogTrigger>
      )}

      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Add Action Item</DialogTitle>
            <DialogDescription>Create a new action item for this incident.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="action-desc">Description</Label>
              <Textarea
                id="action-desc"
                placeholder="What needs to be done?"
                rows={2}
                value={data.description}
                onChange={(e) => setData("description", e.target.value)}
                required
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label>Assignee <span className="text-muted-foreground font-normal">(optional)</span></Label>
              <SearchableSelect
                value={data.assignee_id || null}
                onValueChange={(v) => setData("assignee_id", v ?? "")}
                options={memberOptions(members)}
                placeholder="Unassigned"
                searchPlaceholder="Search members..."
                emptyText="No members found"
                onOpen={() => void loadMembers()}
              />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" disabled={processing}>Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing || !data.description.trim()}>
              {processing ? "Creating…" : "Create"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
