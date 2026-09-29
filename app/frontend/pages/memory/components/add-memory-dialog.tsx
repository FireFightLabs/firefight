import { useForm } from "@inertiajs/react"

import { SearchableSelect } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { CHAT_MEMORY_TEXT_LIMIT } from "@/lib/generated/constants"
import { memoryMemoriesPath } from "@/lib/routes"
import { TextField } from "@/pages/memory/components/text-field"
import { type SubjectOption, subjectParam, WHOLE_WORKSPACE } from "@/pages/memory/types"

interface AddMemoryDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  subjects: SubjectOption[]
}

export function AddMemoryDialog({ open, onOpenChange, subjects }: AddMemoryDialogProps) {
  const { data, setData, transform, post, processing, reset } = useForm({ text: "", subject: WHOLE_WORKSPACE })
  const text = data.text.trim()

  transform((values) => ({ ...values, subject: subjectParam(values.subject) }))

  function submit(event: React.FormEvent) {
    event.preventDefault()
    post(memoryMemoriesPath(), { preserveScroll: true, onSuccess: finish })
  }

  function finish() {
    reset()
    onOpenChange(false)
  }

  function writeText(value: string) {
    setData("text", value)
  }

  function chooseSubject(value: string | null) {
    setData("subject", value ?? WHOLE_WORKSPACE)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Add a memory</DialogTitle>
            <DialogDescription>
              A fact about your systems Halon should know in every incident. It counts as confirmed by you, so Halon trusts it from now on.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 pt-3 pb-5">
            <TextField
              id="memory-text"
              label="What to remember"
              value={data.text}
              limit={CHAT_MEMORY_TEXT_LIMIT}
              placeholder="Such as: checkout reads from the replica, so replica lag shows up as stale carts"
              onChange={writeText}
            />
            <div className="flex flex-col gap-2">
              <Label>About</Label>
              <SearchableSelect
                value={data.subject}
                onValueChange={chooseSubject}
                options={[ { value: WHOLE_WORKSPACE, label: "Whole workspace" }, ...subjects ]}
                placeholder="Whole workspace"
                searchPlaceholder="Search services, teams and resources"
                emptyText="Nothing matches"
              />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" size="sm" disabled={processing}>
                Cancel
              </Button>
            </DialogClose>
            <Button type="submit" size="sm" disabled={processing || text.length === 0 || text.length > CHAT_MEMORY_TEXT_LIMIT}>
              {processing ? "Saving…" : "Remember"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
