// The steps a claim or a theory rests on, each a link down to that step in the story.
export function StepLinks({ steps }: { steps: number[] }) {
  if (steps.length === 0) {
    return null
  }

  return (
    <span className="inline-flex flex-wrap items-center gap-1 text-[11px] text-fg-muted">
      {steps.length === 1 ? "Step" : "Steps"}
      {steps.map((position) => (
        <a
          key={position}
          href={`#step-${position}`}
          className="inline-flex min-w-5 items-center justify-center rounded-full border border-border-strong px-1.5 font-mono tabular-nums text-fg-body transition-colors duration-150 hover:border-brand-border hover:bg-brand-tint hover:text-brand"
        >
          {position}
        </a>
      ))}
    </span>
  )
}
