import { IconExternalLink } from "@tabler/icons-react"

import type {
  IncidentSeveritySettings,
  IncidentTypeSettings,
  RunbookCustomField,
  RunbookSettings,
} from "@/types/serializers"
import { conditionSummary } from "@/pages/settings/lib/runbook-conditions"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"

// Read-only. A runbook is the one settings row that is a document rather than
// a setting, and it is read under time pressure, so opening it must not mean
// opening a form that can be saved by accident.
export function RunbookDetailSheet({
  runbook,
  incidentTypes,
  severities,
  customFields,
  open,
  onOpenChange,
}: {
  runbook: RunbookSettings | null
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
  customFields: RunbookCustomField[]
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  if (!runbook) {
    return null
  }

  const conditions = conditionSummary(
    runbook.conditions ?? [],
    incidentTypes,
    severities,
    customFields,
  )

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="sm:max-w-xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{runbook.name}</SheetTitle>
          {runbook.summary && <SheetDescription>{runbook.summary}</SheetDescription>}
        </SheetHeader>

        <div className="space-y-6 px-4 pb-6">
          <div className="space-y-2">
            <h3 className="text-xs font-medium uppercase text-muted-foreground">Shown when</h3>
            <p className="text-sm">{conditions ?? "Always shown"}</p>
          </div>

          {runbook.externalUrl && (
            <a
              href={runbook.externalUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 text-sm text-primary hover:underline"
            >
              <IconExternalLink className="size-3.5" />
              Open the linked document
            </a>
          )}

          {runbook.content && (
            <>
              <Separator />
              <p className="whitespace-pre-wrap text-sm text-muted-foreground">{runbook.content}</p>
            </>
          )}

          <Separator />

          <div className="space-y-4">
            <h3 className="text-xs font-medium uppercase text-muted-foreground">
              {runbook.steps.length} {runbook.steps.length === 1 ? "step" : "steps"}
            </h3>

            {runbook.steps.length === 0 ? (
              <p className="text-sm text-muted-foreground">This runbook has no steps yet.</p>
            ) : (
              <ol className="space-y-4">
                {runbook.steps.map((step, index) => (
                  <li key={step.id} className="flex gap-3">
                    <Badge variant="outline" className="mt-0.5 size-6 shrink-0 justify-center p-0 font-mono tabular-nums">
                      {index + 1}
                    </Badge>
                    <div className="space-y-1">
                      <p className="text-sm font-medium">{step.title}</p>
                      {step.instruction && (
                        <p className="whitespace-pre-wrap text-sm text-muted-foreground">{step.instruction}</p>
                      )}
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}
