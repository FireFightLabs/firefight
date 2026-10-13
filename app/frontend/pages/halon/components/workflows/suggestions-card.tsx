import { Link, router } from "@inertiajs/react"
import { IconSparkles } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { acceptWorkflowSuggestionPath, dismissWorkflowSuggestionPath, workflowRunPath } from "@/lib/routes"
import type { WorkflowDetail } from "@/types/serializers"
import { formatWhen } from "@/pages/halon/components/workflows/labels"

type Suggestion = WorkflowDetail["suggestions"][number]

// Halon's suggested changes, each a set it made with why and the run that prompted it, waiting for a person.
export function SuggestionsCard({ workflow, canManage }: { workflow: WorkflowDetail; canManage: boolean }) {
  function accept(suggestion: Suggestion) {
    router.post(acceptWorkflowSuggestionPath(workflow.id, suggestion.id), {}, { preserveScroll: true })
  }

  function dismiss(suggestion: Suggestion) {
    router.post(dismissWorkflowSuggestionPath(workflow.id, suggestion.id), {}, { preserveScroll: true })
  }

  if (workflow.suggestions.length === 0) {
    return null
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2"><IconSparkles className="size-4" />Halon&apos;s suggestions</CardTitle>
        <CardDescription className="mt-1">Accepting one adds it to the draft, which is published like any change.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col divide-y">
        {workflow.suggestions.map((suggestion) => (
          <div key={suggestion.id} className="flex flex-col gap-3 py-3 first:pt-0 last:pb-0">
            <p className="text-sm">{suggestion.reason}</p>
            <ul className="list-disc pl-5 text-sm text-fg-secondary">
              {suggestion.changes.map((change) => <li key={change}>{change}</li>)}
            </ul>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="text-xs text-muted-foreground">
                {formatWhen(suggestion.at)}
                {suggestion.runId && (
                  <>
                    {" from "}
                    <Link href={workflowRunPath(workflow.id, suggestion.runId)} className="text-link hover:underline">the run that failed</Link>
                  </>
                )}
              </span>
              {canManage && (
                <div className="flex gap-2">
                  <Button size="sm" variant="outline" onClick={() => dismiss(suggestion)}>Dismiss</Button>
                  <Button size="sm" onClick={() => accept(suggestion)}>Accept</Button>
                </div>
              )}
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}
