import { Link, router, usePage } from "@inertiajs/react"
import { IconRefresh } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { OPERATOR_HALON_ENDINGS } from "@/lib/generated/constants"
import { operatorHalonPath, operatorIncidentPath } from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { RunEnding } from "@/pages/operator/components/run-ending"
import { Trace } from "@/pages/operator/components/trace"
import { dollars, seconds } from "@/pages/operator/lib/format"
import { TONE_CLASSES } from "@/pages/operator/lib/tone"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorHalonRun, OperatorTraceGroup } from "@/types/serializers"

interface RunProps extends OperatorPageProps {
  run: OperatorHalonRun
  promptVersion: string | null
  model: string | null
  groups: OperatorTraceGroup[]
}

function refresh() {
  router.reload()
}

function Chip({ children }: { children: React.ReactNode }) {
  return <span className={`rounded-full border px-2.5 py-1 font-mono ${TONE_CLASSES.neutral}`}>{children}</span>
}

export default function OperatorHalonRun() {
  const { run, promptVersion, model, groups } = usePage<RunProps>().props
  const live = run.ending === OPERATOR_HALON_ENDINGS.LIVE

  return (
    <OperatorLayout title={run.label}>
      <Link href={operatorHalonPath()} className="text-muted-foreground hover:text-foreground mb-3 inline-block text-sm">
        All runs
      </Link>
      <PageHeading
        title={run.label}
        lead="Everything this run did, in order: the job, the facts it started from, every model call and tool call, its self checks, and how the answer reached people. Select a row to read it."
      >
        {live && (
          <Button type="button" variant="outline" size="sm" onClick={refresh}>
            <IconRefresh className="size-3.5" />
            Refresh
          </Button>
        )}
      </PageHeading>
      <div className="mb-6 flex flex-wrap items-center gap-2 text-xs">
        <RunEnding ending={run.ending} />
        {run.notPosted && <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.rose}`}>not posted</span>}
        {run.rehearsal && <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.violet}`}>rehearsal</span>}
        <Chip>{run.turns} of {run.maxTurns} turns</Chip>
        <Chip>{dollars(run.spentMicros)} of {dollars(run.maxSpendMicros)}</Chip>
        <Chip>{seconds(run.seconds)}</Chip>
        {model && <Chip>{model}</Chip>}
        {promptVersion && <Chip>prompt {promptVersion}</Chip>}
        <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.neutral}`}>{run.workspaceName}</span>
        <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.neutral}`}>asked from {run.triggerSource}</span>
        {run.incidentId && (
          <Link href={operatorIncidentPath(run.incidentId)} className={`rounded-full border px-2.5 py-1 hover:underline ${TONE_CLASSES.primary}`}>
            Incident process
          </Link>
        )}
      </div>
      {run.ending !== OPERATOR_HALON_ENDINGS.ANSWERED && run.errorSummary && (
        <p className="text-muted-foreground mb-6 text-sm">
          Recorded cause: <span className="font-mono text-foreground">{run.errorSummary}</span>
        </p>
      )}
      <Trace groups={groups} />
    </OperatorLayout>
  )
}
