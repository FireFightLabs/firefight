import { useForm } from "@inertiajs/react"
import type { ChangeEvent, FormEvent } from "react"

import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { investigationNotesPath } from "@/lib/routes"

// Steers a run while it works. Halon reads the note at its next step, so nobody has to stop it and start again.
export function AddNote({ investigationId }: { investigationId: string }) {
  const { data, setData, post, processing, reset } = useForm({ note: "" })
  const fieldId = `note-${investigationId}`

  function write(event: ChangeEvent<HTMLTextAreaElement>) {
    setData("note", event.target.value)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    post(investigationNotesPath(investigationId), { preserveScroll: true, onSuccess: () => reset() })
  }

  return (
    <form onSubmit={submit} className="ml-[44px] flex flex-col gap-2">
      <Label htmlFor={fieldId}>Tell Halon something</Label>
      <Textarea
        id={fieldId}
        rows={2}
        placeholder="For example, skip GitHub and look at 5xx errors on web"
        className="resize-none"
        value={data.note}
        onChange={write}
      />
      <div className="flex items-center justify-between gap-3">
        <p className="text-xs text-muted-foreground">It reads this at its next step and changes course if it should.</p>
        <Button type="submit" size="sm" disabled={processing || data.note.trim().length === 0}>
          Add to the run
        </Button>
      </div>
    </form>
  )
}
