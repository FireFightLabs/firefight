import { useState } from "react"

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { LESSON_STATUS, LESSON_STATUSES, type LessonStatus } from "@/lib/generated/constants"
import { LessonDialog, LESSON_DECISIONS, type LessonDecision } from "@/pages/memory/components/lesson-dialog"
import { LessonRow } from "@/pages/memory/components/lesson-row"
import { LESSON_STATUS_LABELS } from "@/pages/memory/lib/labels"
import type { ChatLesson } from "@/types/serializers"

const EMPTY: Record<LessonStatus, string> = {
  waiting: "Nothing waiting. Halon writes down what each incident taught when it ends, and the lessons wait here for the incident lead or an admin.",
  approved: "No approved lessons yet. Pull request reviews check a lesson once it is approved.",
  turned_down: "Nothing turned down.",
}

interface LessonsTabProps {
  lessons: ChatLesson[]
  canCurate: boolean
}

export function LessonsTab({ lessons, canCurate }: LessonsTabProps) {
  const [ status, setStatus ] = useState<LessonStatus>(LESSON_STATUS.WAITING)
  const [ deciding, setDeciding ] = useState<{ lesson: ChatLesson; decision: LessonDecision } | null>(null)
  const shown = lessons.filter((lesson) => lesson.status === status)

  function chooseStatus(value: string) {
    const chosen = LESSON_STATUSES.find((each) => each === value)
    if (chosen) {
      setStatus(chosen)
    }
  }

  function closeDecision() {
    setDeciding(null)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Lessons from incidents</CardTitle>
        <CardDescription className="mt-1">
          What incidents taught. Halon checks every pull request against the lessons the incident lead or an admin approved, and comments when a change goes against one. A strict lesson also fails a check on the pull request until the finding is fixed or someone overrides it.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4 p-0">
        <div className="px-6">
          <ToggleGroup type="single" variant="outline" size="sm" value={status} onValueChange={chooseStatus} aria-label="Show" className="flex-wrap">
            {LESSON_STATUSES.map((each) => (
              <ToggleGroupItem key={each} value={each} className="gap-1.5 px-3">
                {LESSON_STATUS_LABELS[each]}
                <span className="text-xs text-muted-foreground tabular-nums">{lessons.filter((lesson) => lesson.status === each).length}</span>
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
        </div>
        {shown.length === 0 ? (
          <p className="px-6 pt-4 pb-10 text-center text-sm text-muted-foreground">{EMPTY[status]}</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="pl-6">Lesson</TableHead>
                <TableHead>From</TableHead>
                <TableHead>Reviews</TableHead>
                {canCurate && <TableHead className="pr-6 text-right">Decide</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {shown.map((lesson) => (
                <LessonRow key={lesson.id} lesson={lesson} canCurate={canCurate} onDecide={setDeciding} />
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
      <LessonDialog
        key={deciding ? `${deciding.lesson.id}:${deciding.decision}` : "none"}
        lesson={deciding?.lesson ?? null}
        decision={deciding?.decision ?? LESSON_DECISIONS.APPROVE}
        onClose={closeDecision}
      />
    </Card>
  )
}
