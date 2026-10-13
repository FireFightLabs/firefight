import { useMemo, useState, type ChangeEvent } from "react"
import { router } from "@inertiajs/react"
import { IconSearch } from "@tabler/icons-react"

import { Blocked } from "@/components/blocked-tooltip"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { copyHalonLibrarySkillPath } from "@/lib/routes"
import type { HalonLibrarySkill } from "@/types/serializers"
import { LibrarySkillSheet } from "@/pages/halon/components/skills/library-skill-sheet"

interface LibraryCardProps {
  library: HalonLibrarySkill[]
  librarySkill: HalonLibrarySkill | null | undefined
  canManage: boolean
}

const FIREFIGHT = "Firefight"

function matches(skill: HalonLibrarySkill, query: string): boolean {
  return [ skill.name, skill.usedWhen, skill.source, skill.domain ].some((text) => text.toLowerCase().includes(query))
}

// Firefight's skills and the ones each connected provider comes with, grouped by whose tools they drive, each with its
// version. Opening one shows its steps, and copying it makes the workspace's own version to change.
export function LibraryCard({ library, librarySkill, canManage }: LibraryCardProps) {
  const [ query, setQuery ] = useState("")
  const [ open, setOpen ] = useState<HalonLibrarySkill | null>(null)
  const [ copying, setCopying ] = useState<string | null>(null)

  const groups = useMemo(() => {
    const wanted = query.trim().toLowerCase()
    const shown = wanted ? library.filter((skill) => matches(skill, wanted)) : library
    const bySource = new Map<string, HalonLibrarySkill[]>()
    shown.forEach((skill) => bySource.set(skill.source, [ ...(bySource.get(skill.source) ?? []), skill ]))
    return [ ...bySource.entries() ].sort(([ left ], [ right ]) => {
      if (left === FIREFIGHT || right === FIREFIGHT) {
        return left === FIREFIGHT ? -1 : 1
      }
      return left.localeCompare(right)
    })
  }, [ library, query ])

  function search(event: ChangeEvent<HTMLInputElement>) {
    setQuery(event.target.value)
  }

  function close() {
    setOpen(null)
  }

  function copy(skill: HalonLibrarySkill) {
    setCopying(skill.name)
    router.post(copyHalonLibrarySkillPath(skill.name), {}, { preserveScroll: true, onSuccess: close, onFinish: () => setCopying(null) })
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <CardTitle>Firefight&apos;s library</CardTitle>
            <CardDescription className="mt-1">
              The skills Halon has from Firefight and your connected tools. Copy one to change how Halon does it here, and you are
              told when Firefight ships a newer version.
            </CardDescription>
          </div>
          <div className="relative w-full sm:w-64">
            <IconSearch className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input value={query} onChange={search} placeholder="Search skills" className="pl-8" aria-label="Search Firefight's skills" />
          </div>
        </div>
      </CardHeader>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Skill</TableHead>
              <TableHead className="hidden md:table-cell">Version</TableHead>
              <TableHead className="w-28" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {groups.length === 0 && (
              <TableRow>
                <TableCell colSpan={3} className="py-8 text-center text-sm text-muted-foreground">No skill matches that.</TableCell>
              </TableRow>
            )}
            {groups.map(([ source, skills ]) => [
              <TableRow key={`group-${source}`} className="hover:bg-transparent">
                <TableCell colSpan={3} className="bg-surface-header py-1.5 text-xs font-medium text-muted-foreground">{source}</TableCell>
              </TableRow>,
              ...skills.map((skill) => (
                <TableRow key={skill.name}>
                  <TableCell className="max-w-0 whitespace-normal">
                    <button type="button" onClick={() => setOpen(skill)} className="text-left font-mono text-sm text-fg-primary hover:underline">
                      {skill.name}
                    </button>
                    <div className="line-clamp-2 text-xs text-muted-foreground">{skill.usedWhen}</div>
                  </TableCell>
                  <TableCell className="hidden text-sm text-muted-foreground md:table-cell">Version {skill.version}</TableCell>
                  <TableCell className="text-right">
                    {canManage && (
                      <Blocked reason={skill.copyBlockedReason}>
                        <Button
                          type="button"
                          size="sm"
                          variant="outline"
                          disabled={skill.copied || copying !== null}
                          onClick={() => copy(skill)}
                        >
                          {skill.copied ? "Copied" : "Copy"}
                        </Button>
                      </Blocked>
                    )}
                  </TableCell>
                </TableRow>
              )),
            ])}
          </TableBody>
        </Table>
      </CardContent>
      <LibrarySkillSheet
        skill={open}
        loaded={librarySkill}
        copyBlockedReason={open?.copyBlockedReason}
        canManage={canManage}
        onCopy={copy}
        onClose={close}
      />
    </Card>
  )
}
