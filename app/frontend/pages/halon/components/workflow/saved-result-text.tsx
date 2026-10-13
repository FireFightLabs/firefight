import { Skeleton } from "@/components/ui/skeleton"
import { useResourceJson } from "@/hooks/use-resource-json"

interface SavedResult {
  name: string
  text: string
}

// The whole of a result a step kept because it was too large to carry, read when it is opened.
export function SavedResultText({ path }: { path: string }) {
  const loaded = useResourceJson<SavedResult>(path)

  if (loaded.state === "loading") {
    return <Skeleton className="h-40 w-full" />
  }
  if (loaded.state === "failed") {
    return <p className="text-sm text-error">The result could not be read. It may have gone with the run&apos;s details.</p>
  }
  return (
    <pre className="max-h-[60dvh] overflow-auto rounded-sm border border-border bg-surface-code p-3 font-mono text-[11.5px] leading-relaxed whitespace-pre-wrap text-fg-primary [overflow-wrap:anywhere]">
      {loaded.answer.text}
    </pre>
  )
}
