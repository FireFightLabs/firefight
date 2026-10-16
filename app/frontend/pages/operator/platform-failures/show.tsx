import { Link, usePage } from "@inertiajs/react"
import { IconArrowLeft } from "@tabler/icons-react"

import { formatDateTime } from "@/lib/formatters"
import { operatorIncidentPath, operatorRootPath, operatorWorkspacePath } from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { SectionCard } from "@/pages/operator/components/section-card"
import { Stat } from "@/pages/operator/components/stat"
import { since } from "@/pages/operator/lib/format"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorPlatformFailure } from "@/types/serializers"

interface PlatformFailureProps extends OperatorPageProps {
  failure: {
    platform: string
    operation: string
    workspace: string
    workspaceId: string
    channel: string | null
    reason: string
    notes: string[]
    firstAt: string
  }
  total: number
  occurrences: OperatorPlatformFailure[]
}

function channelLabel(occurrence: OperatorPlatformFailure): string {
  if (occurrence.channelName) {
    return `#${occurrence.channelName}`
  }
  return occurrence.channel ?? "No channel"
}

export default function OperatorPlatformFailure() {
  const { failure, total, occurrences } = usePage<PlatformFailureProps>().props
  const latest = occurrences[0]
  const where = failure.channel ? `in ${failure.workspace}, channel ${failure.channel}` : `in ${failure.workspace}`

  return (
    <OperatorLayout title={failure.operation}>
      <Link href={operatorRootPath()} className="text-muted-foreground mb-4 inline-flex items-center gap-1 text-xs hover:text-foreground">
        <IconArrowLeft className="size-3.5" />
        Overview
      </Link>
      <PageHeading
        title={<span className="font-mono">{failure.operation}</span>}
        lead={`Every time this ${failure.platform} call failed the same way ${where}, newest first. Failed calls are kept for 30 days.`}
      />

      <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Stat label="Times" value={total} tone="error" note={total > occurrences.length ? `The latest ${occurrences.length} are listed` : "All are listed"} />
        <Stat label="Last failed" value={latest ? since(latest.at) : "-"} note={latest ? formatDateTime(latest.at) : undefined} />
        <Stat label="First failed" value={since(failure.firstAt)} note={formatDateTime(failure.firstAt)} />
      </div>

      <div className="flex flex-col gap-6">
        <SectionCard title={`Why ${failure.platform} refused it`}>
          <div className="flex flex-col gap-2 px-5 py-4">
            <p className="font-mono text-sm text-error">{failure.reason}</p>
            {failure.notes.length > 0 ? (
              <ul className="text-muted-foreground flex list-disc flex-col gap-1 pl-5 text-sm">
                {failure.notes.map((note) => (
                  <li key={note}>{note}</li>
                ))}
              </ul>
            ) : (
              <p className="text-muted-foreground text-sm">{failure.platform} said nothing more than its code.</p>
            )}
            <Link href={operatorWorkspacePath(failure.workspaceId)} className="text-muted-foreground w-fit text-xs hover:text-foreground hover:underline">
              Open {failure.workspace}
            </Link>
          </div>
        </SectionCard>

        <SectionCard title="Occurrences" note={`${total} in all`}>
          <ul className="list-none">
            {occurrences.map((occurrence) => (
              <li key={occurrence.id} className="flex flex-col gap-2 border-b border-border px-5 py-3.5 last:border-b-0">
                <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1 text-sm">
                  <time dateTime={occurrence.at} className="font-mono text-xs">
                    {formatDateTime(occurrence.at)}
                  </time>
                  <span>{occurrence.workspace}</span>
                  <span className="text-muted-foreground font-mono text-xs">{channelLabel(occurrence)}</span>
                  {occurrence.incident && occurrence.incidentId ? (
                    <Link href={operatorIncidentPath(occurrence.incidentId)} className="font-mono text-xs hover:underline">
                      {occurrence.incident}
                    </Link>
                  ) : (
                    <span className="text-muted-foreground text-xs">No incident</span>
                  )}
                  <span className="text-muted-foreground font-mono text-xs">{occurrence.errorClass}</span>
                </div>
                <pre className="bg-muted/40 max-h-72 overflow-auto rounded-md border border-border p-3 font-mono text-xs whitespace-pre-wrap break-all">
                  {occurrence.message ?? "No message was recorded."}
                </pre>
              </li>
            ))}
          </ul>
        </SectionCard>
      </div>
    </OperatorLayout>
  )
}
