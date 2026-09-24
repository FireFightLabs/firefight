// The steps a claim or a theory rests on, each a link down to that step in the story.
export function StepLinks({ steps }: { steps: number[] }) {
  if (steps.length === 0) {
    return null
  }

  return (
    <span className="inline-flex flex-wrap items-center gap-1 text-[11px] text-muted-foreground">
      {steps.length === 1 ? "Step" : "Steps"}
      {steps.map((position) => (
        <a
          key={position}
          href={`#step-${position}`}
          className="inline-flex min-w-5 items-center justify-center rounded-full border border-border px-1.5 font-mono tabular-nums text-foreground/90 transition-colors hover:border-primary/50 hover:text-primary"
        >
          {position}
        </a>
      ))}
    </span>
  )
}
