import { useEffect } from "react"
import { router } from "@inertiajs/react"
import { IconDownload, IconLoader2 } from "@tabler/icons-react"

import { Blocked } from "@/components/blocked-tooltip"
import { MarkdownText } from "@/components/markdown-text"
import { Button } from "@/components/ui/button"
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { SKILL_FILE_NAME, SKILL_PAGE_PROPS, SKILL_PAGE_QUERIES } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { exportHalonLibrarySkillPath } from "@/lib/routes"
import type { HalonLibrarySkill } from "@/types/serializers"

interface LibrarySkillSheetProps {
  skill: HalonLibrarySkill | null
  // The opened skill with its steps, loaded when the sheet opens.
  loaded: HalonLibrarySkill | null | undefined
  copyBlockedReason: string | undefined
  canManage: boolean
  onCopy: (skill: HalonLibrarySkill) => void
  onClose: () => void
}

// One of Firefight's skills as Halon reads it, with its version, to read before copying it or to take as a file.
export function LibrarySkillSheet({ skill, loaded, copyBlockedReason, canManage, onCopy, onClose }: LibrarySkillSheetProps) {
  const name = skill?.name ?? null
  const shown = loaded && loaded.name === name ? loaded : null

  useEffect(() => {
    if (!name) {
      return
    }
    router.reload({ only: [ SKILL_PAGE_PROPS.LIBRARY_SKILL ], data: { [SKILL_PAGE_QUERIES.LIBRARY]: name } })
  }, [ name ])

  function copy() {
    if (skill) {
      onCopy(skill)
    }
  }

  return (
    <Sheet open={skill !== null} onOpenChange={whenClosed(onClose)}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
        <SheetHeader>
          <SheetTitle className="font-mono">{skill?.name}</SheetTitle>
          <SheetDescription>
            {skill?.source}&apos;s skill, version {skill?.version}. {skill?.usedWhen}
          </SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-4 px-4 pb-4">
          <div className="flex flex-col gap-1">
            <span className="text-xs font-medium text-muted-foreground">Tools</span>
            <p className="font-mono text-xs text-fg-secondary [overflow-wrap:anywhere]">{skill?.tools.join(", ")}</p>
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-xs font-medium text-muted-foreground">Steps</span>
            {shown?.steps
              ? <MarkdownText text={shown.steps} className="text-fg-body" />
              : (
                <span className="flex items-center gap-2 text-sm text-muted-foreground">
                  <IconLoader2 className="size-4 motion-safe:animate-spin" />
                  Loading its steps
                </span>
              )}
          </div>
        </div>
        <SheetFooter className="flex-row flex-wrap gap-2">
          {canManage && (
            <Blocked reason={copyBlockedReason} side="top">
              <Button type="button" disabled={Boolean(copyBlockedReason)} onClick={copy}>Copy to change it</Button>
            </Blocked>
          )}
          {name && (
            <Button type="button" variant="outline" asChild>
              <a href={exportHalonLibrarySkillPath(name)} download>
                <IconDownload className="size-4" />
                Export {SKILL_FILE_NAME}
              </a>
            </Button>
          )}
        </SheetFooter>
      </SheetContent>
    </Sheet>
  )
}
