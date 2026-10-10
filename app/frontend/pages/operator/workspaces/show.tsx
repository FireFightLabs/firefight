import { Link, usePage } from "@inertiajs/react"
import { IconArrowLeft } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { operatorWorkspacesPath, sandboxOperatorWorkspacePath } from "@/lib/routes"
import { FilterBar } from "@/pages/operator/components/filter-bar"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { SectionCard } from "@/pages/operator/components/section-card"
import { Stat } from "@/pages/operator/components/stat"
import { useAction } from "@/pages/operator/hooks/use-action"
import { dollars, seconds } from "@/pages/operator/lib/format"
import type { FilterProps, OperatorPageProps } from "@/pages/operator/types"
import type { OperatorSandboxFailover, OperatorSandboxFix } from "@/types/serializers"

interface WorkspaceProps extends OperatorPageProps, Omit<FilterProps, "workspaces"> {
  workspace: { id: string; name: string }
  placement: string
  choices: { value: string; label: string }[]
  sandboxMicros: number
  aiMicros: number
  failoverCount: number
  failovers: OperatorSandboxFailover[]
  fixes: OperatorSandboxFix[]
}

export default function OperatorWorkspace() {
  const { workspace, placement, choices, sandboxMicros, aiMicros, failoverCount, failovers, fixes, filter, windows } = usePage<WorkspaceProps>().props
  const [chosen, setChosen] = useState(placement)
  const { busy, post } = useAction()

  function save() {
    post(sandboxOperatorWorkspacePath(workspace.id), { placement: chosen })
  }

  return (
    <OperatorLayout title={workspace.name}>
      <Link href={operatorWorkspacesPath()} className="text-muted-foreground mb-4 inline-flex items-center gap-1 text-xs hover:text-foreground">
        <IconArrowLeft className="size-3.5" />
        Workspaces
      </Link>
      <PageHeading
        title={workspace.name}
        lead="Where this workspace's code sandboxes run, the boxes that started on the backup because the provider before it could not start them, and what each code fix cost."
      />
      <FilterBar filter={filter} windows={windows} />

      <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Stat label="Sandbox cost" value={dollars(sandboxMicros)} note="Boxes started in the window" />
        <Stat label="AI cost of code fixes" value={dollars(aiMicros)} note="Model calls of the fixes in the window" />
        <Stat
          label="Failovers"
          value={failoverCount}
          tone={failoverCount > 0 ? "warning" : "neutral"}
          note={failoverCount > 0 ? "Started on the backup" : "Every box started where it was sent"}
        />
      </div>

      <div className="flex flex-col gap-6">
        <SectionCard title="Where its code sandboxes run">
          <div className="flex flex-col gap-3 px-5 py-4">
            <Label htmlFor="sandbox-placement" className="text-foreground">
              Run this workspace&apos;s code sandboxes on
            </Label>
            <div className="flex flex-wrap items-center gap-3">
              <Select value={chosen} onValueChange={setChosen}>
                <SelectTrigger id="sandbox-placement" className="w-96 max-w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {choices.map((choice) => (
                    <SelectItem key={choice.value} value={choice.value}>
                      {choice.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Button type="button" size="sm" onClick={save} disabled={busy || chosen === placement}>
                Save
              </Button>
            </div>
            <p className="text-muted-foreground max-w-prose text-sm">
              Following the deployment, a box starts on its main provider, and on the backup when the main one cannot
              start it. Held to one provider, every box runs there and never fails over, so its code stays where it was
              put, such as a provider in the region its data must stay in.
            </p>
          </div>
        </SectionCard>

        <SectionCard title="Failovers" note={failoverCount > failovers.length ? `The latest ${failovers.length} of ${failoverCount}` : undefined}>
          {failovers.length > 0 ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>When</TableHead>
                  <TableHead>Refused by</TableHead>
                  <TableHead>Started on</TableHead>
                  <TableHead>Why</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {failovers.map((failover) => (
                  <TableRow key={failover.id}>
                    <TableCell className="text-muted-foreground whitespace-nowrap">{formatDateTime(failover.at)}</TableCell>
                    <TableCell>{failover.from}</TableCell>
                    <TableCell>{failover.to}</TableCell>
                    <TableCell className="text-muted-foreground max-w-md text-xs whitespace-normal">{failover.reason}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <p className="text-muted-foreground px-5 py-8 text-center text-sm">No box failed over in the window.</p>
          )}
        </SectionCard>

        <SectionCard title="Code fixes" note="Sandbox cost is the boxes the fix's run used while the fix ran">
          {fixes.length > 0 ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Started</TableHead>
                  <TableHead>Repository</TableHead>
                  <TableHead>Ran on</TableHead>
                  <TableHead className="text-right">Sandbox time</TableHead>
                  <TableHead className="text-right">Sandbox cost</TableHead>
                  <TableHead className="text-right">AI cost</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {fixes.map((fix) => (
                  <TableRow key={fix.id}>
                    <TableCell className="text-muted-foreground whitespace-nowrap">{formatDateTime(fix.at)}</TableCell>
                    <TableCell>
                      {fix.pullRequestUrl ? (
                        <a href={fix.pullRequestUrl} className="font-mono text-[13px] hover:underline" target="_blank" rel="noreferrer">
                          {fix.repository}
                        </a>
                      ) : (
                        <span className="font-mono text-[13px]">{fix.repository}</span>
                      )}
                    </TableCell>
                    <TableCell className="text-muted-foreground">{fix.providers.length > 0 ? fix.providers.join(", ") : "-"}</TableCell>
                    <TableCell className="text-right font-mono tabular-nums">{seconds(fix.sandboxSeconds)}</TableCell>
                    <TableCell className="text-right font-mono tabular-nums">{dollars(fix.sandboxMicros)}</TableCell>
                    <TableCell className="text-right font-mono tabular-nums">{dollars(fix.aiMicros)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <p className="text-muted-foreground px-5 py-8 text-center text-sm">No code fix in the window.</p>
          )}
        </SectionCard>
      </div>
    </OperatorLayout>
  )
}
