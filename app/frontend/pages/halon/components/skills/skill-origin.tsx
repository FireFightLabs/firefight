import { Badge } from "@/components/ui/badge"
import type { HalonSkill } from "@/types/serializers"

// Where a skill came from: the workspace's own, or a copy of Firefight's with the library version it holds and a
// marker when Firefight shipped a newer one, which opens what changed.
export function SkillOrigin({ skill, onUpdate }: { skill: HalonSkill; onUpdate: () => void }) {
  if (!skill.copyOf) {
    return <span className="text-muted-foreground">Your own</span>
  }

  return (
    <div className="flex flex-col items-start gap-1">
      <span className="text-muted-foreground">Copy of Firefight&apos;s, version {skill.libraryVersion}</span>
      {skill.libraryUpdate && (
        <button type="button" onClick={onUpdate} className="rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand">
          <Badge variant="outline" className="border-warning text-warning">Version {skill.libraryUpdate.version} is out</Badge>
        </button>
      )}
    </div>
  )
}
