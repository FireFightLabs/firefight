import { Link, usePage } from "@inertiajs/react"
import { IconTrash } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { TONE_CLASSES } from "@/components/investigations/tone"
import { Button } from "@/components/ui/button"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { cleanUpOperatorSandboxesPath, deleteOperatorSandboxesPath, stopOperatorSandboxesPath } from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { SectionCard } from "@/pages/operator/components/section-card"
import { Stat } from "@/pages/operator/components/stat"
import { OPERATOR_SANDBOX_KINDS, OPERATOR_SANDBOX_PURPOSES } from "@/pages/operator/generated/constants"
import { useAction } from "@/pages/operator/hooks/use-action"
import { dollars, since } from "@/pages/operator/lib/format"
import { FLAG_LABELS, FLAG_TONES, PHASE_LABELS, bytes, duration, isActive } from "@/pages/operator/lib/sandboxes"
import { SandboxTimeline } from "@/pages/operator/sandboxes/timeline"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorSandboxAction, OperatorSandboxBox, OperatorSandboxCopy, OperatorSandboxTotals } from "@/types/serializers"

interface SandboxesProps extends OperatorPageProps {
  totals: OperatorSandboxTotals
  reads: { provider: string; readAt: string | null; error: string | null }[]
  boxes: OperatorSandboxBox[]
  copies: OperatorSandboxCopy[]
  actions: OperatorSandboxAction[]
  windowStart: string
  now: string
  cleanUpBlockedReason: string | null
}

// What a confirmation asks before it posts.
interface Asking {
  title: string
  description: string
  confirmLabel: string
  url: string
  data: Record<string, string>
}

const ACTION_WORDS: Record<OperatorSandboxAction["actionName"], string> = {
  stop: "stopped",
  delete: "deleted",
  clean_up: "cleaned up",
}

function Flags({ flags }: { flags: OperatorSandboxBox["flags"] }) {
  return (
    <span className="flex flex-wrap gap-1">
      {flags.map((flag) => (
        <span key={flag} className={`rounded-full border px-2 py-px text-[11px] font-medium ${TONE_CLASSES[FLAG_TONES[flag]]}`}>
          {FLAG_LABELS[flag]}
        </span>
      ))}
    </span>
  )
}

function Origin({ box }: { box: OperatorSandboxBox }) {
  if (!box.origin) {
    return <span className="text-muted-foreground">No record</span>
  }
  if (!box.origin.href) {
    return <span className="text-muted-foreground font-mono text-[12px]">{box.origin.label}</span>
  }
  return (
    <Link href={box.origin.href} className="hover:underline">
      {box.origin.label}
    </Link>
  )
}

export default function OperatorSandboxes() {
  const { totals, reads, boxes, copies, actions, windowStart, now, cleanUpBlockedReason } = usePage<SandboxesProps>().props
  const [asking, setAsking] = useState<Asking | null>(null)
  const { busy, post } = useAction()
  const running = totals.running.reduce((sum, provider) => sum + provider.count, 0)
  const failedReads = reads.filter((read) => read.error)
  const priced = (box: OperatorSandboxBox) => (box.costMicros === null || box.costMicros === undefined ? "-" : dollars(box.costMicros))

  function stopAsking() {
    setAsking(null)
  }

  function confirm() {
    if (!asking) {
      return
    }
    post(asking.url, asking.data)
    setAsking(null)
  }

  function askToStop(box: OperatorSandboxBox) {
    setAsking({
      title: `Stop ${box.name ?? box.ref}?`,
      description: box.recorded
        ? `The run using it starts a new box the next time it reads code. ${box.providerName} stops billing for it.`
        : `Firefight has no record of this box, so nothing is using it. ${box.providerName} stops billing for it.`,
      confirmLabel: "Stop box",
      url: stopOperatorSandboxesPath(),
      data: { provider: box.provider, ref: box.ref },
    })
  }

  function askToDelete(box: OperatorSandboxBox) {
    setAsking({
      title: `Delete ${box.name ?? box.ref}?`,
      description: box.recorded
        ? `${box.providerName} deletes the box and everything on its disk for good. The run using it starts a new box the next time it reads code.`
        : `${box.providerName} deletes the box and everything on its disk for good. Firefight has no record of it, so nothing is using it.`,
      confirmLabel: "Delete box",
      url: deleteOperatorSandboxesPath(),
      data: { provider: box.provider, ref: box.ref, kind: OPERATOR_SANDBOX_KINDS.BOX },
    })
  }

  function askToDeleteCopy(copy: OperatorSandboxCopy) {
    const what = copy.repository ? `${copy.repository}'s prepared copy` : "the copy of the sandbox image"
    setAsking({
      title: `Delete ${copy.ref}?`,
      description: `${copy.providerName} lets go of ${what} for good. The next box that needs it installs from nothing and keeps a new one.`,
      confirmLabel: "Delete copy",
      url: deleteOperatorSandboxesPath(),
      data: { provider: copy.provider, ref: copy.ref, kind: OPERATOR_SANDBOX_KINDS.SNAPSHOT },
    })
  }

  function askToCleanUp() {
    setAsking({
      title: `Delete ${totals.rogue} rogue ${totals.rogue === 1 ? "sandbox" : "sandboxes and copies"}?`,
      description: "Every box and kept copy a provider holds that Firefight has no record of is deleted for good. Nothing uses them, so no run is affected.",
      confirmLabel: "Delete all rogue",
      url: cleanUpOperatorSandboxesPath(),
      data: {},
    })
  }

  return (
    <OperatorLayout title="Sandboxes">
      <PageHeading
        title="Sandboxes"
        lead="Every code sandbox and kept copy each provider holds, set against what Firefight recorded, so one with no record, left running or stuck stands out. The sweep reads the providers every 10 minutes."
      >
        <Button type="button" size="sm" variant="outline" onClick={askToCleanUp} disabled={busy || Boolean(cleanUpBlockedReason)} title={cleanUpBlockedReason ?? undefined}>
          <IconTrash className="size-3.5" />
          Clean up rogue
        </Button>
      </PageHeading>

      {failedReads.length > 0 && (
        <div className={`mb-6 rounded-lg border px-4 py-3 text-sm ${TONE_CLASSES.warning}`}>
          {failedReads.map((read) => (
            <p key={read.provider}>
              {read.provider} could not be read{read.readAt ? ` at ${formatDateTime(read.readAt)}` : ""}, so what it holds may be out of date. {read.error}
            </p>
          ))}
        </div>
      )}

      <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Stat
          label="Running now"
          value={running}
          note={totals.running.length > 0 ? totals.running.map((provider) => `${provider.name} ${provider.count}`).join(" · ") : "Nothing running"}
        />
        <Stat label="Cost today" value={dollars(totals.todayMicros)} note="Boxes and kept copies" />
        <Stat label="Cost this month" value={dollars(totals.monthMicros)} note="Boxes and kept copies" />
        <Stat label="Failovers" value={totals.failovers} tone={totals.failovers > 0 ? "warning" : "neutral"} note="Last 24 hours" />
        <Stat label="No record" value={totals.rogue} tone={totals.rogue > 0 ? "error" : "neutral"} note={totals.rogue > 0 ? "Held with no record in Firefight" : "Every one is accounted for"} />
      </div>

      <div className="flex flex-col gap-6">
        <SectionCard title="Last 24 hours" note="One lane per provider. Red has no record or failed, amber is overdue or stuck.">
          <SandboxTimeline boxes={boxes} windowStart={windowStart} now={now} />
        </SectionCard>

        <SectionCard title="Boxes" note={`${boxes.length} in the last 24 hours`}>
          {boxes.length > 0 ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Box</TableHead>
                  <TableHead>State</TableHead>
                  <TableHead>Started by</TableHead>
                  <TableHead>Age</TableHead>
                  <TableHead>Last used</TableHead>
                  <TableHead className="text-right">Cost so far</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {boxes.map((box) => (
                  <TableRow key={box.key}>
                    <TableCell>
                      <div className="flex flex-col">
                        <span className="font-mono text-[12px]">{box.name ?? box.ref}</span>
                        <span className="text-muted-foreground text-xs">
                          {box.providerName}
                          {box.size ? ` · ${box.size}` : ""}
                          {box.workspaceName ? ` · ${box.workspaceName}` : ""}
                        </span>
                      </div>
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-col gap-1">
                        <span className="text-xs">{box.phase ? PHASE_LABELS[box.phase] : (box.state ?? "Unknown")}</span>
                        <Flags flags={box.flags} />
                      </div>
                    </TableCell>
                    <TableCell className="text-xs">
                      <Origin box={box} />
                    </TableCell>
                    <TableCell className="text-muted-foreground font-mono text-xs">{since(box.startedAt, new Date(now))}</TableCell>
                    <TableCell className="text-muted-foreground font-mono text-xs">{box.lastUsedAt ? since(box.lastUsedAt, new Date(now)) : "-"}</TableCell>
                    <TableCell className="text-right font-mono text-xs tabular-nums">
                      <div className="flex flex-col">
                        <span>{priced(box)}</span>
                        <span className="text-muted-foreground">{duration(box.seconds)}</span>
                      </div>
                    </TableCell>
                    <TableCell className="text-right">
                      {box.held && (
                        <div className="flex justify-end gap-1">
                          {isActive(box.phase) && (
                            <Button type="button" size="sm" variant="outline" onClick={() => askToStop(box)} disabled={busy}>
                              Stop
                            </Button>
                          )}
                          <Button type="button" size="sm" variant="ghost" onClick={() => askToDelete(box)} disabled={busy}>
                            Delete
                          </Button>
                        </div>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <p className="text-muted-foreground px-5 py-8 text-center text-sm">No box in the last 24 hours.</p>
          )}
        </SectionCard>

        <SectionCard title="Kept copies" note="Prepared repositories and copies of the sandbox image">
          {copies.length > 0 ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Copy</TableHead>
                  <TableHead>Holds</TableHead>
                  <TableHead>Age</TableHead>
                  <TableHead>Last used</TableHead>
                  <TableHead className="text-right">Size</TableHead>
                  <TableHead className="text-right">Storage a month</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {copies.map((copy) => (
                  <TableRow key={copy.key}>
                    <TableCell>
                      <div className="flex flex-col">
                        <span className="font-mono text-[12px]">{copy.ref}</span>
                        <span className="text-muted-foreground text-xs">{copy.providerName}</span>
                      </div>
                    </TableCell>
                    <TableCell className="text-xs">
                      <div className="flex flex-col gap-1">
                        <span>
                          {copy.purpose === OPERATOR_SANDBOX_PURPOSES.IMAGE
                            ? "The sandbox image"
                            : [copy.repository, copy.workspaceName].filter(Boolean).join(" · ") || "A prepared repository"}
                        </span>
                        <Flags flags={copy.flags} />
                      </div>
                    </TableCell>
                    <TableCell className="text-muted-foreground font-mono text-xs">{since(copy.createdAt, new Date(now))}</TableCell>
                    <TableCell className="text-muted-foreground font-mono text-xs">{copy.lastUsedAt ? since(copy.lastUsedAt, new Date(now)) : "-"}</TableCell>
                    <TableCell className="text-right font-mono text-xs tabular-nums">{bytes(copy.byteSize)}</TableCell>
                    <TableCell className="text-right font-mono text-xs tabular-nums">{copy.monthlyMicros > 0 ? dollars(copy.monthlyMicros) : "Free"}</TableCell>
                    <TableCell className="text-right">
                      <Button type="button" size="sm" variant="ghost" onClick={() => askToDeleteCopy(copy)} disabled={busy}>
                        Delete
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <p className="text-muted-foreground px-5 py-8 text-center text-sm">No kept copies.</p>
          )}
        </SectionCard>

        {actions.length > 0 && (
          <SectionCard title="What operators did">
            <ul className="divide-y divide-border">
              {actions.map((action) => (
                <li key={action.id} className="flex flex-wrap items-baseline gap-x-3 gap-y-0.5 px-5 py-2.5 text-xs">
                  <span className="text-muted-foreground font-mono">{formatDateTime(action.at)}</span>
                  <span>
                    {action.operator} {ACTION_WORDS[action.actionName]} <span className="font-mono">{action.ref}</span> on {action.providerName}
                  </span>
                  {action.outcome && <span className="text-error">{action.outcome}</span>}
                </li>
              ))}
            </ul>
          </SectionCard>
        )}
      </div>

      <ConfirmDeleteDialog
        open={asking !== null}
        title={asking?.title ?? ""}
        description={asking?.description ?? ""}
        confirmLabel={asking?.confirmLabel}
        onConfirm={confirm}
        onCancel={stopAsking}
      />
    </OperatorLayout>
  )
}
