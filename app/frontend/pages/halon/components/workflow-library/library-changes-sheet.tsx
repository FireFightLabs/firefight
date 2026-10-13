import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconMinus, IconPencil, IconPlus } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { WORKFLOW_CHANGE_KINDS } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { keepOwnHalonWorkflowPath, takeLibraryHalonWorkflowPath } from "@/lib/routes"
import type { HalonLibraryWorkflowUse } from "@/types/serializers"

interface LibraryChangesSheetProps {
  workflow: HalonLibraryWorkflowUse | null
  canManage: boolean
  onClose: () => void
}

type ChangeKind = (typeof WORKFLOW_CHANGE_KINDS)[keyof typeof WORKFLOW_CHANGE_KINDS]

const CHANGE_MARKS: Record<ChangeKind, { icon: typeof IconPlus; tone: string; words: string }> = {
  [WORKFLOW_CHANGE_KINDS.ADDED]: { icon: IconPlus, tone: "text-success", words: "Added" },
  [WORKFLOW_CHANGE_KINDS.REMOVED]: { icon: IconMinus, tone: "text-error", words: "Removed" },
  [WORKFLOW_CHANGE_KINDS.CHANGED]: { icon: IconPencil, tone: "text-warning", words: "Changed" },
}

// What Firefight changed in a library workflow since the workspace copied it. The copy stays as it is until a person
// takes the new version into a draft or keeps their own.
export function LibraryChangesSheet({ workflow, canManage, onClose }: LibraryChangesSheetProps) {
  const [ sending, setSending ] = useState(false)
  const update = workflow?.libraryUpdate ?? null

  function doneSending() {
    setSending(false)
  }

  function take() {
    if (!workflow) {
      return
    }
    setSending(true)
    router.post(takeLibraryHalonWorkflowPath(workflow.id), {}, { preserveScroll: true, onSuccess: onClose, onFinish: doneSending })
  }

  function keep() {
    if (!workflow) {
      return
    }
    setSending(true)
    router.post(keepOwnHalonWorkflowPath(workflow.id), {}, { preserveScroll: true, onSuccess: onClose, onFinish: doneSending })
  }

  return (
    <Sheet open={workflow !== null && update !== null} onOpenChange={whenClosed(onClose)}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
        <SheetHeader>
          <SheetTitle>Firefight&apos;s version {update?.version} of {workflow?.itemName}</SheetTitle>
          <SheetDescription>
            What Firefight changed since {workflow?.name} took version {workflow?.libraryVersion}. Your workflow stays as it is until
            you choose. Taking the new version opens a draft holding it, with your own trigger, for you to look at and publish.
          </SheetDescription>
        </SheetHeader>
        <ul className="flex flex-col gap-2 px-4">
          {update?.changes.map((change, index) => {
            const mark = CHANGE_MARKS[change.kind]
            const Icon = mark.icon
            return (
              <li key={`${change.kind}-${index}`} className="flex items-start gap-2 text-sm text-fg-body">
                <Icon className={`mt-0.5 size-4 shrink-0 ${mark.tone}`} aria-label={mark.words} />
                {change.text}
              </li>
            )
          })}
        </ul>
        {canManage && (
          <SheetFooter className="flex-row flex-wrap gap-2">
            <Button type="button" disabled={sending} onClick={take}>Take it into a draft</Button>
            <Button type="button" variant="outline" disabled={sending} onClick={keep}>Keep mine</Button>
          </SheetFooter>
        )}
      </SheetContent>
    </Sheet>
  )
}
