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
import { CHAT_INSTRUCTION_TEXT_LIMIT } from "@/lib/generated/constants"
import { memoryInstructionPath, memoryInstructionsPath } from "@/lib/routes"
import { TextField } from "@/pages/memory/components/text-field"
import { type SubjectOption, subjectParam, WHOLE_WORKSPACE } from "@/pages/memory/types"
import type { ChatInstruction } from "@/types/serializers"

interface InstructionDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  instruction: ChatInstruction | null
  scopes: SubjectOption[]
}

// Owns both writing new instructions and editing a note. Where they apply is fixed once written.
export function InstructionDialog({ open, onOpenChange, instruction, scopes }: InstructionDialogProps) {
  const { data, setData, transform, post, patch, processing, reset } = useForm({
    text: instruction?.text ?? "",
    subject: scopes.some((option) => option.value === WHOLE_WORKSPACE) ? WHOLE_WORKSPACE : "",
  })
  const text = data.text.trim()
  const unchanged = instruction !== null && text === instruction.text.trim()

  transform((values) => ({ ...values, subject: subjectParam(values.subject) }))

  function submit(event: React.FormEvent) {
    event.preventDefault()
    const options = { preserveScroll: true, onSuccess: finish }
    if (instruction) {
      patch(memoryInstructionPath(instruction.id), options)
    } else {
      post(memoryInstructionsPath(), options)
    }
  }

  function finish() {
    reset()
    onOpenChange(false)
  }

  function writeText(value: string) {
    setData("text", value)
  }

  function chooseScope(value: string | null) {
    if (value) {
      setData("subject", value)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-xl">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{instruction ? "Edit instructions" : "Add instructions"}</DialogTitle>
            <DialogDescription>
              How Halon should work, such as where to look first or what never to touch. Halon follows them in every chat and investigation that
              involves where they apply, and never treats them as evidence.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 pt-3 pb-5">
            {instruction && (
              <p className="text-sm">
                <span className="text-muted-foreground">Applies to</span> <span className="font-medium">{instruction.label}</span>
              </p>
            )}
            {!instruction && (
              <div className="flex flex-col gap-2">
                <Label>Applies to</Label>
                <SearchableSelect
                  value={data.subject || null}
                  onValueChange={chooseScope}
                  options={scopes}
                  placeholder="Pick where they apply"
                  searchPlaceholder="Search services, teams and resources"
                  emptyText="Everything here has instructions already"
                />
              </div>
            )}
            <TextField
              id="instruction-text"
              label="Instructions"
              rows={8}
              className="min-h-44"
              value={data.text}
              limit={CHAT_INSTRUCTION_TEXT_LIMIT}
              placeholder={"Such as:\nCheck the Northflank logs for the worker before the web service.\nNever suggest restarting the primary database, page the data team instead."}
              onChange={writeText}
            />
            {instruction && <p className="text-xs text-muted-foreground">The current wording is kept as history when you save.</p>}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" size="sm" disabled={processing}>
                Cancel
              </Button>
            </DialogClose>
            <Button
              type="submit"
              size="sm"
              disabled={processing || unchanged || text.length === 0 || text.length > CHAT_INSTRUCTION_TEXT_LIMIT || (!instruction && !data.subject)}
            >
              {processing ? "Saving…" : "Save instructions"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
