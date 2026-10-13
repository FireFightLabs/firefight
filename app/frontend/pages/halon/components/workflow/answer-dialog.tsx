import { router } from "@inertiajs/react"
import { type ChangeEvent, useState } from "react"

import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Textarea } from "@/components/ui/textarea"
import { workflowRunQuestionAnswerPath } from "@/lib/routes"
import type { Ask } from "@/pages/halon/components/workflow/ask-panel"
import { RUN_VISIT } from "@/pages/halon/hooks/use-workflow-edits"

interface AnswerDialogProps {
  workflowId: string
  runId: string
  ask: Ask
  open: boolean
  onOpenChange: (open: boolean) => void
}

// Answering a question with a short form: one of its choices when it has any, and every field. Send stays off until
// each is given, and the run carries on with what is sent.
export function AnswerDialog({ workflowId, runId, ask, open, onOpenChange }: AnswerDialogProps) {
  const [ choice, setChoice ] = useState("")
  const [ values, setValues ] = useState<Record<string, string>>({})
  const complete = (ask.choices.length === 0 || choice.length > 0) && ask.fields.every((field) => (values[field.name] ?? "").trim().length > 0)

  function typed(name: string) {
    return (event: ChangeEvent<HTMLTextAreaElement>) => setValues({ ...values, [name]: event.target.value })
  }

  function close() {
    onOpenChange(false)
  }

  function send() {
    router.post(workflowRunQuestionAnswerPath(workflowId, runId, ask.id), { choice, values }, { ...RUN_VISIT, onSuccess: close })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Answer</DialogTitle>
          <DialogDescription className="[overflow-wrap:anywhere]">{ask.question}</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          {ask.choices.length > 0 && (
            <div className="space-y-1.5">
              <Label className="text-xs">Your choice</Label>
              <RadioGroup value={choice} onValueChange={setChoice} aria-label="Your choice">
                {ask.choices.map((each) => (
                  <div key={each.value} className="flex items-center gap-2">
                    <RadioGroupItem id={`answer-${ask.id}-${each.value}`} value={each.value} />
                    <Label htmlFor={`answer-${ask.id}-${each.value}`} className="text-sm font-normal">{each.label}</Label>
                  </div>
                ))}
              </RadioGroup>
            </div>
          )}
          {ask.fields.map((field) => (
            <div key={field.name} className="space-y-1">
              <Label htmlFor={`answer-${ask.id}-${field.name}`} className="text-xs">{field.label}</Label>
              <Textarea id={`answer-${ask.id}-${field.name}`} value={values[field.name] ?? ""} onChange={typed(field.name)} rows={3} />
            </div>
          ))}
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={close}>Cancel</Button>
          <Button type="button" disabled={!complete} onClick={send}>Send answer</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
