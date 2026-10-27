import { useForm } from "@inertiajs/react"
import type { FormEvent } from "react"

import { TextField } from "@/components/memory/text-field"
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
import { Switch } from "@/components/ui/switch"
import { whenClosed } from "@/lib/handlers"
import { CHAT_MEMORY_TEXT_LIMIT } from "@/lib/generated/constants"
import { approveLessonPath, editLessonPath, turnDownLessonPath } from "@/lib/routes"
import type { ChatLesson } from "@/types/serializers"

export const LESSON_DECISIONS = { APPROVE: "approve", EDIT: "edit", TURN_DOWN: "turn_down" } as const
export type LessonDecision = (typeof LESSON_DECISIONS)[keyof typeof LESSON_DECISIONS]

interface LessonDialogProps {
  lesson: ChatLesson | null
  decision: LessonDecision
  onClose: () => void
}

const COPY: Record<LessonDecision, { title: string; description: string; submit: string }> = {
  approve: {
    title: "Approve this lesson",
    description: "Halon checks every pull request against it from now on, and comments when a change goes against it.",
    submit: "Approve",
  },
  edit: {
    title: "Edit this lesson",
    description: "Your wording replaces it as a lesson approved by you. The old wording is kept as rejected so Halon does not learn it again.",
    submit: "Save and approve",
  },
  turn_down: {
    title: "Turn down this lesson",
    description: "Pull request reviews never check it, Halon stops using it, and it is not learned again from a later incident.",
    submit: "Turn down",
  },
}

// Approving and editing both leave the lesson approved, and both say whether it is strict. Turning down asks only why.
export function LessonDialog({ lesson, decision, onClose }: LessonDialogProps) {
  const { data, setData, post, patch, processing } = useForm({ text: lesson?.text ?? "", strict: lesson?.strict ?? false, reason: "" })
  const copy = COPY[decision]
  const editing = decision === LESSON_DECISIONS.EDIT
  const turningDown = decision === LESSON_DECISIONS.TURN_DOWN
  const text = data.text.trim()
  const invalid = editing && (text.length === 0 || text.length > CHAT_MEMORY_TEXT_LIMIT || (text === lesson?.text.trim() && data.strict === lesson?.strict))

  function submit(event: FormEvent) {
    event.preventDefault()
    if (!lesson) {
      return
    }
    const options = { preserveScroll: true, preserveState: true, onSuccess: onClose }
    if (editing) {
      patch(editLessonPath(lesson.id), options)
    } else if (turningDown) {
      post(turnDownLessonPath(lesson.id), options)
    } else {
      post(approveLessonPath(lesson.id), options)
    }
  }

  function writeText(value: string) {
    setData("text", value)
  }

  function writeReason(value: string) {
    setData("reason", value)
  }

  function chooseStrict(checked: boolean) {
    setData("strict", checked)
  }

  return (
    <Dialog open={lesson !== null} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{copy.title}</DialogTitle>
            <DialogDescription>{copy.description}</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 pt-3 pb-5">
            {!editing && lesson && <blockquote className="edge-bar rounded-lg bg-muted/40 px-3 py-2 [--edge-bar:var(--border-strong)] text-sm">{lesson.text}</blockquote>}
            {editing && <TextField id="lesson-text" label="Lesson" value={data.text} limit={CHAT_MEMORY_TEXT_LIMIT} onChange={writeText} />}
            {turningDown ? (
              <TextField id="lesson-reason" label="Why" optional rows={2} value={data.reason} placeholder="Such as: that only held during the migration" onChange={writeReason} />
            ) : (
              <div className="flex items-start justify-between gap-6">
                <div>
                  <Label htmlFor="lesson-strict" className="text-foreground">
                    Strict
                  </Label>
                  <p className="mt-1 text-sm text-muted-foreground">
                    A pull request that goes against it also gets a failing check, until the finding is fixed or someone overrides it.
                  </p>
                </div>
                <Switch id="lesson-strict" checked={data.strict} onCheckedChange={chooseStrict} />
              </div>
            )}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" size="sm" disabled={processing}>
                Cancel
              </Button>
            </DialogClose>
            <Button type="submit" size="sm" variant={turningDown ? "destructive" : "default"} disabled={processing || invalid}>
              {processing ? "Saving…" : copy.submit}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
