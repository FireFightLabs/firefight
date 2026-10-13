import { useEffect, useState } from "react"
import { router } from "@inertiajs/react"
import { IconLoader2 } from "@tabler/icons-react"

import { Blocked } from "@/components/blocked-tooltip"
import { MarkdownText } from "@/components/markdown-text"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { formatDateTime } from "@/lib/formatters"
import { SKILL_PAGE_PROPS, SKILL_PAGE_QUERIES } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { restoreHalonSkillPath } from "@/lib/routes"
import type { HalonSkill, HalonSkillVersion } from "@/types/serializers"

interface SkillHistorySheetProps {
  skill: HalonSkill | null
  history: HalonSkillVersion[] | null | undefined
  canManage: boolean
  onClose: () => void
}

const STATUS_WORDS: Record<HalonSkillVersion["status"], string> = {
  live: "Live",
  retired: "Earlier",
  dismissed: "Dismissed",
  edited: "Halon's, edited before it went live",
}

// Every version a skill had, newest first, with who wrote it and why. Any earlier one can come back, as a new version,
// so history is never rewritten.
export function SkillHistorySheet({ skill, history, canManage, onClose }: SkillHistorySheetProps) {
  const [ loadedFor, setLoadedFor ] = useState<string | null>(null)
  const [ restoring, setRestoring ] = useState<string | null>(null)
  const skillId = skill?.id ?? null
  const loaded = skillId !== null && loadedFor === skillId && history

  useEffect(() => {
    if (!skillId) {
      return
    }
    router.reload({
      only: [ SKILL_PAGE_PROPS.HISTORY ],
      data: { [SKILL_PAGE_QUERIES.HISTORY]: skillId },
      onSuccess: () => setLoadedFor(skillId),
    })
  }, [ skillId ])

  function restore(version: HalonSkillVersion) {
    if (!skill) {
      return
    }
    setRestoring(version.id)
    router.post(restoreHalonSkillPath(skill.id), { version_id: version.id }, {
      preserveScroll: true,
      onSuccess: onClose,
      onFinish: () => setRestoring(null),
    })
  }

  return (
    <Sheet open={skill !== null} onOpenChange={whenClosed(onClose)}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
        <SheetHeader>
          <SheetTitle>History of {skill?.name}</SheetTitle>
          <SheetDescription>Every version is kept, newest first. Bringing one back makes it the next version.</SheetDescription>
        </SheetHeader>
        {!loaded && (
          <div className="flex items-center gap-2 px-4 text-sm text-muted-foreground">
            <IconLoader2 className="size-4 motion-safe:animate-spin" />
            Loading its versions
          </div>
        )}
        {loaded && (
          <ol className="flex flex-col gap-6 px-4 pb-6">
            {history.map((version) => (
              <li key={version.id} className="flex flex-col gap-2 border-l border-border pl-4">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-medium">Version {version.number}</span>
                  <Badge variant={version.status === "live" ? "secondary" : "outline"}>{STATUS_WORDS[version.status]}</Badge>
                </div>
                <span className="text-xs text-muted-foreground">{version.author}, {formatDateTime(version.at)}</span>
                {version.reason && <p className="text-sm text-fg-body">{version.reason}</p>}
                <details className="group">
                  <summary className="cursor-pointer text-xs font-medium text-muted-foreground hover:text-fg-primary">What it said</summary>
                  <div className="mt-2 flex flex-col gap-2">
                    <p className="text-sm text-fg-body">{version.usedWhen}</p>
                    <p className="font-mono text-xs text-muted-foreground">{version.tools.join(", ") || "No tools"}</p>
                    <MarkdownText text={version.steps} className="text-fg-muted" />
                  </div>
                </details>
                {canManage && version.status !== "live" && (
                  <Blocked reason={version.restoreBlockedReason} side="top">
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      className="w-fit"
                      disabled={Boolean(version.restoreBlockedReason) || restoring !== null}
                      onClick={() => restore(version)}
                    >
                      {restoring === version.id && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
                      Bring back version {version.number}
                    </Button>
                  </Blocked>
                )}
              </li>
            ))}
          </ol>
        )}
      </SheetContent>
    </Sheet>
  )
}
