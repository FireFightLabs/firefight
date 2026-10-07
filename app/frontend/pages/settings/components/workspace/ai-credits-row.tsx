import { Button } from "@/components/ui/button"

export interface AiCredits {
  title: string
  detail: string
  action?: { label: string; href: string }
}

// Firefight credits come after the workspace's own accounts and cannot be moved or removed here, so they sit under the
// list rather than in it. Only Firefight's cloud sells them, so elsewhere there is nothing to draw. Where they are bought
// is the hosted build's to say, and only someone who manages the accounts is offered it.
export function AiCreditsRow({ credits, canManage }: { credits: AiCredits; canManage: boolean }) {
  return (
    <div className="flex items-center justify-between gap-4 border-t px-4 py-3">
      <div className="flex flex-col gap-0.5">
        <span className="text-sm font-medium">{credits.title}</span>
        <span className="text-xs text-muted-foreground">{credits.detail}</span>
      </div>
      {canManage && credits.action && (
        <Button size="sm" variant="outline" className="shrink-0" asChild>
          <a href={credits.action.href}>{credits.action.label}</a>
        </Button>
      )}
    </div>
  )
}
