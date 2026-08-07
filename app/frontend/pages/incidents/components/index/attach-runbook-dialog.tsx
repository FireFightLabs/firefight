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
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { incidentRunbooksPath } from "@/lib/routes"

export interface AttachableRunbook {
  slug: string
  name: string
}

function runbookOptions(runbooks: AttachableRunbook[]): SearchableSelectOption[] {
  return runbooks.map((runbook) => ({ value: runbook.slug, label: runbook.name }))
}

export function AttachRunbookDialog({
  incidentId,
  runbooks,
}: {
  incidentId: string
  runbooks: AttachableRunbook[]
}) {
  const [open, setOpen] = useState(false)
  const { data, setData, post, processing, reset } = useForm({ slug: "" })
  const noneLeft = runbooks.length === 0

  function handleSubmit(event: React.FormEvent) {
    event.preventDefault()
    post(incidentRunbooksPath(incidentId), {
      preserveScroll: true,
      onSuccess: () => {
        setOpen(false)
        reset()
      },
    })
  }

  function selectRunbook(value: string | null) {
    setData("slug", value ?? "")
  }

  const trigger = (
    <Button
      variant="ghost"
      size="icon"
      className="size-7 text-foreground/60 hover:text-foreground hover:bg-muted/50 disabled:opacity-40 disabled:pointer-events-none"
      aria-label="Attach runbook"
      disabled={noneLeft}
    >
      <IconPlus className="size-4" />
    </Button>
  )

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      {noneLeft ? (
        <Tooltip>
          <TooltipTrigger asChild>
            <span>{trigger}</span>
          </TooltipTrigger>
          <TooltipContent>Every runbook is already attached</TooltipContent>
        </Tooltip>
      ) : (
        <DialogTrigger asChild>{trigger}</DialogTrigger>
      )}

      <DialogContent onOpenAutoFocus={(event) => event.preventDefault()}>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Attach runbook</DialogTitle>
            <DialogDescription>
              Its steps are posted in the incident channel for responders to claim.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-2 pt-3 pb-5">
            <Label>Runbook</Label>
            <SearchableSelect
              value={data.slug || null}
              onValueChange={selectRunbook}
              options={runbookOptions(runbooks)}
              placeholder="Pick a runbook"
              searchPlaceholder="Search runbooks..."
              emptyText="No runbooks found"
            />
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing || !data.slug}>Attach</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
