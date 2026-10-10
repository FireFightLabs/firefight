import { Link, usePage } from "@inertiajs/react"

import { Card } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { operatorHalonBenchesPath, operatorHalonBenchPath } from "@/lib/routes"
import { benchStartedBy, DIMENSIONS, score, ScoreChange } from "@/pages/operator/components/bench-score"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Stat } from "@/pages/operator/components/stat"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorHalonBenchComparison, OperatorHalonBenchRun } from "@/types/serializers"

interface BenchCompareProps extends OperatorPageProps {
  base: OperatorHalonBenchRun
  head: OperatorHalonBenchRun
  comparison: OperatorHalonBenchComparison
}

type Sides = OperatorHalonBenchComparison["total"]

function change(sides: Sides): number | null {
  return sides.base === null || sides.head === null ? null : sides.head - sides.base
}

type Row = OperatorHalonBenchComparison["rows"][number]

// The scenarios that dropped most first, since those are where to read the replay.
function byChange(left: Row, right: Row): number {
  return (left.delta ?? 0) - (right.delta ?? 0)
}

function sidesText(sides: Sides): string {
  return `${score(sides.base)} to ${score(sides.head)}`
}

function verdict(comparison: OperatorHalonBenchComparison): string {
  if (comparison.shared === 0) {
    return "The two runs have no scored scenario in common, so there is nothing to compare."
  }
  if (!comparison.comparable) {
    return "The two runs used different models, so a change here says how the models differ, not whether Halon got worse."
  }
  if (comparison.failed) {
    return `The newer run dropped by more than ${comparison.tolerance}, more than the noise between two replays. Read the scenarios that dropped most first.`
  }
  return `The newer run holds, within ${comparison.tolerance} of the older.`
}

function RunSide({ label, run }: { label: string; run: OperatorHalonBenchRun }) {
  return (
    <div className="flex min-w-0 flex-col gap-0.5 text-sm">
      <span className="text-muted-foreground text-[11px] font-medium tracking-[0.12em] uppercase">{label}</span>
      <Link href={operatorHalonBenchPath(run.id)} className="font-medium hover:underline">
        Prompt {run.promptVersion} on {run.model}
      </Link>
      <span className="text-muted-foreground text-xs">
        {benchStartedBy(run)}, {formatDateTime(run.createdAt)}
      </span>
    </div>
  )
}

export default function OperatorHalonBenchCompare() {
  const { base, head, comparison } = usePage<BenchCompareProps>().props
  const tone = comparison.failed ? "error" : "neutral"

  return (
    <OperatorLayout title="Compare bench runs">
      <Link href={operatorHalonBenchesPath()} className="text-muted-foreground hover:text-foreground mb-3 inline-block text-sm">
        All bench runs
      </Link>
      <PageHeading
        title="Compare bench runs"
        lead={`Only the ${comparison.shared} scenarios both runs scored count in either total, so adding or removing a scenario never moves the comparison.`}
      />

      <Card className="mb-6 grid gap-4 px-5 py-4 sm:grid-cols-2">
        <RunSide label="Older" run={base} />
        <RunSide label="Newer" run={head} />
      </Card>

      <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Stat label="Total" value={<ScoreChange change={change(comparison.total)} tolerance={comparison.tolerance} />} note={sidesText(comparison.total)} tone={tone} />
        {DIMENSIONS.map((dimension) => (
          <Stat
            key={dimension.key}
            label={dimension.label}
            value={<ScoreChange change={change(comparison.dimensions[dimension.key])} tolerance={comparison.tolerance} />}
            note={sidesText(comparison.dimensions[dimension.key])}
          />
        ))}
      </div>

      <p className={`mb-4 text-sm ${tone === "error" ? "text-error" : "text-muted-foreground"}`}>{verdict(comparison)}</p>

      <Card className="gap-0 overflow-hidden py-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Scenario</TableHead>
              <TableHead className="text-right">Older</TableHead>
              <TableHead className="text-right">Newer</TableHead>
              <TableHead className="text-right">Change</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {[...comparison.rows].sort(byChange).map((row) => (
              <TableRow key={row.scenario}>
                <TableCell className="whitespace-normal">
                  <span className="block font-medium">{row.title}</span>
                  <span className="text-muted-foreground font-mono text-xs">{row.scenario}</span>
                </TableCell>
                <TableCell className="text-right font-mono tabular-nums">{score(row.base)}</TableCell>
                <TableCell className="text-right font-mono tabular-nums">{score(row.head)}</TableCell>
                <TableCell className="text-right">
                  <ScoreChange change={row.delta} tolerance={comparison.tolerance} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </OperatorLayout>
  )
}
