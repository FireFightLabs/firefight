export interface AiCredits {
  title: string
  detail: string
}

// Firefight credits come after the workspace's own accounts and cannot be moved or removed here, so they sit under the
// list rather than in it. Only Firefight's cloud sells them, so elsewhere there is nothing to draw.
export function AiCreditsRow({ credits }: { credits: AiCredits }) {
  return (
    <div className="flex flex-col gap-0.5 border-t px-4 py-3">
      <span className="text-sm font-medium">{credits.title}</span>
      <span className="text-xs text-muted-foreground">{credits.detail}</span>
    </div>
  )
}
