import { useState } from "react"
import { router } from "@inertiajs/react"

import { SkillContentDiff } from "@/components/skills/skill-content-diff"
import { Button } from "@/components/ui/button"
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { whenClosed } from "@/lib/handlers"
import { keepOwnHalonSkillPath, takeLibraryHalonSkillPath } from "@/lib/routes"
import type { HalonSkill } from "@/types/serializers"

interface LibraryUpdateSheetProps {
  skill: HalonSkill | null
  canManage: boolean
  onClose: () => void
}

// What Firefight changed in a skill since the workspace copied it. The copy stays as it is until a person takes the new
// version or keeps their own.
export function LibraryUpdateSheet({ skill, canManage, onClose }: LibraryUpdateSheetProps) {
  const [ sending, setSending ] = useState(false)
  const update = skill?.libraryUpdate ?? null

  function doneSending() {
    setSending(false)
  }

  function take() {
    if (!skill) {
      return
    }
    setSending(true)
    router.post(takeLibraryHalonSkillPath(skill.id), {}, { preserveScroll: true, onSuccess: onClose, onFinish: doneSending })
  }

  function keep() {
    if (!skill) {
      return
    }
    setSending(true)
    router.post(keepOwnHalonSkillPath(skill.id), {}, { preserveScroll: true, onSuccess: onClose, onFinish: doneSending })
  }

  return (
    <Sheet open={skill !== null && update !== null} onOpenChange={whenClosed(onClose)}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-3xl">
        <SheetHeader>
          <SheetTitle>Firefight&apos;s version {update?.version} of {skill?.name}</SheetTitle>
          <SheetDescription>
            What Firefight changed since you copied version {skill?.libraryVersion}. Your copy stays as it is until you choose.
            Taking Firefight&apos;s version replaces what your copy says, and your words stay in its history.
          </SheetDescription>
        </SheetHeader>
        {update && skill && (
          <div className="px-4">
            <SkillContentDiff
              before={update.before}
              after={update.after}
              beforeLabel={`Version ${skill.libraryVersion}, which you copied`}
              afterLabel={`Firefight's version ${update.version}`}
            />
          </div>
        )}
        {canManage && (
          <SheetFooter className="flex-row flex-wrap gap-2">
            <Button type="button" disabled={sending} onClick={take}>Take Firefight&apos;s version</Button>
            <Button type="button" variant="outline" disabled={sending} onClick={keep}>Keep mine</Button>
          </SheetFooter>
        )}
      </SheetContent>
    </Sheet>
  )
}
