import { Blocked } from "@/components/blocked-tooltip"
import { Button } from "@/components/ui/button"
import { TableCell, TableRow } from "@/components/ui/table"
import { formatDate } from "@/lib/formatters"
import { LESSON_STATUS } from "@/lib/generated/constants"
import { OriginLink } from "@/pages/memory/components/origin-link"
import { LESSON_DECISIONS, type LessonDecision } from "@/pages/memory/components/lesson-dialog"
import { LESSON_STATUS_LABELS, LESSON_STATUS_TONES, lessonStanding } from "@/pages/memory/lib/labels"
import type { ChatLesson } from "@/types/serializers"

interface LessonRowProps {
  lesson: ChatLesson
  canCurate: boolean
  onDecide: (choice: { lesson: ChatLesson; decision: LessonDecision }) => void
}

// Approve, Edit and Turn down stay on every row. Only the incident lead or an admin may use them, and a button the lesson
// refuses is inert with why as its tooltip.
export function LessonRow({ lesson, canCurate, onDecide }: LessonRowProps) {
  const approveReason = lesson.approveBlockedReason ?? undefined
  const editReason = lesson.editBlockedReason ?? undefined
  const turnDownReason = lesson.turnDownBlockedReason ?? undefined

  function approve() {
    onDecide({ lesson, decision: LESSON_DECISIONS.APPROVE })
  }

  function edit() {
    onDecide({ lesson, decision: LESSON_DECISIONS.EDIT })
  }

  function turnDown() {
    onDecide({ lesson, decision: LESSON_DECISIONS.TURN_DOWN })
  }

  return (
    <TableRow className="align-top">
      <TableCell className="max-w-xl min-w-64 pl-6 whitespace-normal">
        <div className="flex flex-col gap-1.5 py-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className={`rounded-full border px-2 py-0.5 text-[11px] font-medium ${LESSON_STATUS_TONES[lesson.status]}`}>{LESSON_STATUS_LABELS[lesson.status]}</span>
            {lesson.status === LESSON_STATUS.APPROVED && lesson.strict && (
              <span className="rounded-full border border-error/35 bg-error-tint px-2 py-0.5 text-[11px] font-medium text-error">Strict</span>
            )}
            {lesson.about && <span className="text-xs text-muted-foreground">About {lesson.about}</span>}
          </div>
          <p className="text-sm leading-relaxed">{lesson.text}</p>
          {lesson.reason && <p className="text-xs text-muted-foreground">{lesson.reason}</p>}
        </div>
      </TableCell>
      <TableCell className="min-w-48 whitespace-normal">
        <div className="flex flex-col gap-0.5 py-1 text-sm">
          <OriginLink url={lesson.originUrl} elsewhere={lesson.originElsewhere} className="hover:underline">
            {lesson.origin}
          </OriginLink>
          <span className="text-xs text-muted-foreground">Learned {formatDate(lesson.createdAt)}</span>
        </div>
      </TableCell>
      <TableCell className="min-w-48 text-sm whitespace-normal text-muted-foreground">
        <div className="py-1">{lessonStanding(lesson)}</div>
      </TableCell>
      {canCurate && (
        <TableCell className="pr-6 text-right">
          <div className="flex items-center justify-end gap-1.5 py-0.5">
            <Blocked reason={approveReason}>
              <Button type="button" size="sm" variant="outline" disabled={Boolean(approveReason)} onClick={approve}>
                Approve
              </Button>
            </Blocked>
            <Blocked reason={editReason}>
              <Button type="button" size="sm" variant="outline" disabled={Boolean(editReason)} onClick={edit}>
                Edit
              </Button>
            </Blocked>
            <Blocked reason={turnDownReason}>
              <Button type="button" size="sm" variant="ghost" className="text-muted-foreground" disabled={Boolean(turnDownReason)} onClick={turnDown}>
                Turn down
              </Button>
            </Blocked>
          </div>
        </TableCell>
      )}
    </TableRow>
  )
}
