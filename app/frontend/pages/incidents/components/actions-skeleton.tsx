import { Skeleton } from "@/components/ui/skeleton"

export function ActionsSkeleton() {
  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-3">
      <Skeleton className="h-4 w-20" />
      <Skeleton className="h-1 w-full rounded-full" />
      {Array.from({ length: 3 }).map((_, i) => (
        <div key={i} className="flex items-center gap-2">
          <Skeleton className="size-4 shrink-0 rounded-full" />
          <Skeleton className="h-4 flex-1" />
        </div>
      ))}
    </div>
  )
}
