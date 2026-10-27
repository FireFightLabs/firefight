import { useForm } from "@inertiajs/react"
import { type FormEvent, useEffect, useRef, useState } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { TextField } from "@/components/memory/text-field"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDate } from "@/lib/formatters"
import { whenClosed } from "@/lib/handlers"
import { overrideFindingPath } from "@/lib/routes"
import { OriginLink } from "@/pages/memory/components/origin-link"
import type { HeldPullRequestFinding } from "@/types/serializers"

interface HeldPullRequestsProps {
  findings: HeldPullRequestFinding[]
  // The review a pull request's check linked to, whose rows are marked.
  focusedReviewId: string | null
}

// Pull requests a strict lesson holds with a failing check, and those someone let through, each with the lesson that
// found it. Shown only while there is one, since most workspaces have none.
// Override stays on every row. Whoever may not override sees it inert, with who can as its tooltip.
export function HeldPullRequests({ findings, focusedReviewId }: HeldPullRequestsProps) {
  const [ overriding, setOverriding ] = useState<HeldPullRequestFinding | null>(null)

  function closeOverride() {
    setOverriding(null)
  }

  if (findings.length === 0) {
    return null
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Pull requests held by strict lessons</CardTitle>
        <CardDescription className="mt-1">
          Each of these has a failing Halon review check until the finding is fixed. Override one to let the pull request through, saying why.
        </CardDescription>
      </CardHeader>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="pl-6">Pull request</TableHead>
              <TableHead>Finding</TableHead>
              <TableHead>Check</TableHead>
              <TableHead className="pr-6 text-right">Decide</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {findings.map((finding) => (
              <HeldRow key={finding.id} finding={finding} focused={finding.reviewId === focusedReviewId} onOverride={setOverriding} />
            ))}
          </TableBody>
        </Table>
      </CardContent>
      <OverrideDialog key={overriding?.id ?? "none"} finding={overriding} onClose={closeOverride} />
    </Card>
  )
}

interface HeldRowProps {
  finding: HeldPullRequestFinding
  focused: boolean
  onOverride: (finding: HeldPullRequestFinding) => void
}

function HeldRow({ finding, focused, onOverride }: HeldRowProps) {
  const row = useRef<HTMLTableRowElement>(null)
  const blocked = finding.overrideBlockedReason ?? undefined
  const name = `#${finding.number}${finding.title ? ` ${finding.title}` : ""}`

  useEffect(() => {
    if (focused) {
      row.current?.scrollIntoView({ block: "center" })
    }
  }, [ focused ])

  function override() {
    onOverride(finding)
  }

  return (
    <TableRow ref={row} data-focused={focused || undefined} className="align-top data-[focused]:bg-brand-tint">
      <TableCell className="min-w-48 pl-6 whitespace-normal">
        <div className="flex flex-col gap-0.5 py-1 text-sm">
          {finding.url ? (
            <a href={finding.url} target="_blank" rel="noreferrer" className="hover:underline">
              {name}
            </a>
          ) : (
            <span>{name}</span>
          )}
          <span className="text-xs text-muted-foreground">{finding.repository}</span>
        </div>
      </TableCell>
      <TableCell className="max-w-xl min-w-64 whitespace-normal">
        <div className="flex flex-col gap-1 py-1">
          <p className="text-sm leading-relaxed">{finding.claim}</p>
          <OriginLink url={finding.lessonUrl} elsewhere={finding.lessonElsewhere} className="text-xs text-muted-foreground hover:underline">
            {finding.lessonLabel}
          </OriginLink>
        </div>
      </TableCell>
      <TableCell className="min-w-48 text-sm whitespace-normal text-muted-foreground">
        <div className="py-1">
          {finding.overriddenAt ? (
            <>
              Overridden by {finding.overriddenBy}, {formatDate(finding.overriddenAt)}
              {finding.overrideReason && <div className="text-xs">{finding.overrideReason}</div>}
            </>
          ) : (
            <span className="text-error">Failing</span>
          )}
          {finding.checkProblem && <div className="text-xs">{finding.checkProblem}</div>}
        </div>
      </TableCell>
      <TableCell className="pr-6 text-right">
        <div className="py-0.5">
          <Blocked reason={blocked}>
            <Button type="button" size="sm" variant="outline" disabled={Boolean(blocked)} onClick={override}>
              Override
            </Button>
          </Blocked>
        </div>
      </TableCell>
    </TableRow>
  )
}

interface OverrideDialogProps {
  finding: HeldPullRequestFinding | null
  onClose: () => void
}

function OverrideDialog({ finding, onClose }: OverrideDialogProps) {
  const { data, setData, post, processing } = useForm({ reason: "" })
  const invalid = data.reason.trim().length === 0

  function submit(event: FormEvent) {
    event.preventDefault()
    if (finding) {
      post(overrideFindingPath(finding.id), { preserveScroll: true, preserveState: true, onSuccess: onClose })
    }
  }

  function writeReason(value: string) {
    setData("reason", value)
  }

  return (
    <Dialog open={finding !== null} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Override this finding</DialogTitle>
            <DialogDescription>
              The pull request is no longer held by it, and its Halon review check passes once nothing else holds it. The finding stays on the pull request.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 pt-3 pb-5">
            {finding && <blockquote className="edge-bar rounded-lg bg-muted/40 px-3 py-2 [--edge-bar:var(--border-strong)] text-sm">{finding.claim}</blockquote>}
            <TextField id="override-reason" label="Why" rows={2} value={data.reason} placeholder="Such as: the timeout change ships behind a flag that stays off" onChange={writeReason} />
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" size="sm" disabled={processing}>
                Cancel
              </Button>
            </DialogClose>
            <Button type="submit" size="sm" disabled={processing || invalid}>
              {processing ? "Saving…" : "Override"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
