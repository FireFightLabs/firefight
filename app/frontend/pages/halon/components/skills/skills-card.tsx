import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconFileImport, IconPlus, IconSparkles } from "@tabler/icons-react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { disableHalonSkillPath, enableHalonSkillPath, halonSkillPath } from "@/lib/routes"
import { timeAgo } from "@/lib/time"
import type { HalonSkill, HalonSkillVersion } from "@/types/serializers"
import { SkillHistorySheet } from "@/pages/halon/components/skills/skill-history-sheet"
import { LibraryUpdateSheet } from "@/pages/halon/components/skills/library-update-sheet"
import { SkillOrigin } from "@/pages/halon/components/skills/skill-origin"
import { SkillRowActions } from "@/pages/halon/components/skills/skill-row-actions"

interface SkillsCardProps {
  skills: HalonSkill[]
  // The versions of the skill whose history is open, loaded when it opens.
  history: HalonSkillVersion[] | null | undefined
  canManage: boolean
  onCreate: () => void
  onImport: () => void
  onEdit: (skill: HalonSkill) => void
}

function plural(count: number, word: string): string {
  return `${count} ${word}${count === 1 ? "" : "s"}`
}

// What deleting loses, named: the versions, and for a copy that Halon goes back to Firefight's skill, which the
// workflows that run it use from then on.
function deleteDescription(skill: HalonSkill | null): string {
  if (!skill) {
    return ""
  }
  const versions = `its ${plural(skill.versionCount, "version")}`
  if (skill.copyOf) {
    const workflows = skill.usageCount > 0 ? ` The ${plural(skill.usageCount, "workflow")} that run it use Firefight's from then on.` : ""
    return `Your copy of ${skill.copyOf} and ${versions} are deleted, and Halon uses Firefight's ${skill.copyOf} again.${workflows}`
  }
  return `${skill.name} and ${versions} are deleted, and Halon no longer loads it. This cannot be undone.`
}

// What turning a skill off does to the workflows that run it, named, so nobody turns one off without knowing.
function switchOffDescription(skill: HalonSkill | null): string {
  if (!skill) {
    return ""
  }
  return `${plural(skill.usageCount, "workflow")} ${skill.usageCount === 1 ? "runs" : "run"} ${skill.name}. While it is off, their step that runs it fails, and they cannot be published, until you turn it back on.`
}

function switchSkill(skill: HalonSkill, on: boolean) {
  router.patch(on ? enableHalonSkillPath(skill.id) : disableHalonSkillPath(skill.id), {}, { preserveScroll: true })
}

// The workspace's own skills, each with its version and who wrote it, and the copies of Firefight's with whether a newer
// version came out.
export function SkillsCard({ skills, history, canManage, onCreate, onImport, onEdit }: SkillsCardProps) {
  const [ deleting, setDeleting ] = useState<HalonSkill | null>(null)
  const [ historyOf, setHistoryOf ] = useState<HalonSkill | null>(null)
  const [ updateOf, setUpdateOf ] = useState<HalonSkill | null>(null)
  const [ switchingOff, setSwitchingOff ] = useState<HalonSkill | null>(null)

  // A skill a workflow runs is turned off only once the person has read what that stops. A copy is not in the way, since
  // Firefight's own skill of its name takes over.
  function toggle(skill: HalonSkill) {
    if (skill.enabled && skill.usageCount > 0 && !skill.copyOf) {
      setSwitchingOff(skill)
      return
    }
    switchSkill(skill, !skill.enabled)
  }

  function cancelSwitchOff() {
    setSwitchingOff(null)
  }

  function confirmSwitchOff() {
    if (switchingOff) {
      switchSkill(switchingOff, false)
    }
    setSwitchingOff(null)
  }

  function cancelDelete() {
    setDeleting(null)
  }

  function confirmDelete() {
    if (!deleting) {
      return
    }
    router.delete(halonSkillPath(deleting.id), { preserveScroll: true, onFinish: cancelDelete })
  }

  function closeHistory() {
    setHistoryOf(null)
  }

  function closeUpdate() {
    setUpdateOf(null)
  }

  const header = (
    <CardHeader>
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <CardTitle>Your skills</CardTitle>
          <CardDescription className="mt-1">
            Recipes Halon loads when a question fits, beside Firefight&apos;s. A copy of one of Firefight&apos;s is used in its place.
          </CardDescription>
        </div>
        {canManage && (
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={onImport}>
              <IconFileImport className="size-4" />
              Import SKILL.md
            </Button>
            <Button size="sm" onClick={onCreate}>
              <IconPlus className="size-4" />
              New skill
            </Button>
          </div>
        )}
      </div>
    </CardHeader>
  )

  const sheets = (
    <>
      <SkillHistorySheet skill={historyOf} history={history} canManage={canManage} onClose={closeHistory} />
      <LibraryUpdateSheet skill={updateOf} canManage={canManage} onClose={closeUpdate} />
    </>
  )

  if (skills.length === 0) {
    return (
      <Card>
        {header}
        <CardContent>
          <div className="rounded-xl border border-dashed border-border px-6 py-10 text-center">
            <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-lg bg-muted">
              <IconSparkles className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No skills of your own yet</p>
            <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-muted-foreground">
              Write down how your team does something, such as rotating a key, copy one of Firefight&apos;s below to change it,
              or ask Halon in a chat to save what it just did as a skill.
            </p>
            {canManage && (
              <Button size="sm" variant="outline" className="mt-4" onClick={onCreate}>
                <IconPlus className="size-3.5" />
                Write your first skill
              </Button>
            )}
          </div>
        </CardContent>
        {sheets}
      </Card>
    )
  }

  return (
    <Card>
      {header}
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-16">On</TableHead>
              <TableHead className="w-2/5">Skill</TableHead>
              <TableHead className="hidden lg:table-cell">Tools</TableHead>
              <TableHead className="hidden md:table-cell">Version</TableHead>
              <TableHead className="hidden sm:table-cell">From</TableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {skills.map((skill) => (
              <TableRow key={skill.id}>
                <TableCell>
                  <Switch
                    checked={skill.enabled}
                    disabled={!canManage}
                    onCheckedChange={() => toggle(skill)}
                    aria-label={`${skill.name} is ${skill.enabled ? "on" : "off"}`}
                  />
                </TableCell>
                <TableCell className="max-w-0 whitespace-normal">
                  <div className="font-mono text-sm text-fg-primary">{skill.name}</div>
                  <div className="line-clamp-2 text-xs text-muted-foreground">{skill.usedWhen}</div>
                </TableCell>
                <TableCell className="hidden text-sm text-muted-foreground lg:table-cell">{plural(skill.tools.length, "tool")}</TableCell>
                <TableCell className="hidden text-sm md:table-cell">
                  <div>Version {skill.version}</div>
                  <div className="text-xs text-muted-foreground">{skill.updatedBy}, {timeAgo(skill.updatedAt)}</div>
                </TableCell>
                <TableCell className="hidden text-sm sm:table-cell">
                  <SkillOrigin skill={skill} onUpdate={() => setUpdateOf(skill)} />
                </TableCell>
                <TableCell>
                  <SkillRowActions
                    skill={skill}
                    canManage={canManage}
                    onEdit={() => onEdit(skill)}
                    onHistory={() => setHistoryOf(skill)}
                    onLibraryUpdate={() => setUpdateOf(skill)}
                    onDelete={() => setDeleting(skill)}
                  />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
      {sheets}
      {canManage && (
        <ConfirmDeleteDialog
          open={Boolean(switchingOff)}
          title={`Turn ${switchingOff?.name ?? "this skill"} off?`}
          description={switchOffDescription(switchingOff)}
          confirmLabel="Turn off"
          onConfirm={confirmSwitchOff}
          onCancel={cancelSwitchOff}
        />
      )}
      {canManage && (
        <ConfirmDeleteDialog
          open={Boolean(deleting)}
          title={`Delete ${deleting?.name ?? "this skill"}?`}
          description={deleteDescription(deleting)}
          onConfirm={confirmDelete}
          onCancel={cancelDelete}
        />
      )}
    </Card>
  )
}
