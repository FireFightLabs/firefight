// An action's key, with its title and what it allows when the key alone does not say enough.
export function ActionLabel({
  actionKey,
  title,
  description,
}: {
  actionKey: string
  title?: string | null
  description?: string | null
}) {
  if (!title) {
    return <code className="min-w-0 flex-1 truncate text-xs">{actionKey}</code>
  }

  return (
    <span className="flex min-w-0 flex-1 flex-col gap-0.5">
      <span className="flex min-w-0 items-baseline gap-2">
        <span className="truncate text-sm">{title}</span>
        <code className="text-muted-foreground shrink-0 text-xs">{actionKey}</code>
      </span>
      {description && <span className="text-muted-foreground text-xs font-normal">{description}</span>}
    </span>
  )
}
