const BAR_HEIGHTS = [ 5, 8, 11 ]

// Three rising bars, the first `filled` drawn solid, so severity reads without its colour.
export function SeverityBars({ filled }: { filled: number }) {
  return (
    <svg viewBox="0 0 14 14" className="size-3.5 shrink-0" aria-hidden="true">
      {BAR_HEIGHTS.map((height, index) => (
        <rect
          key={height}
          x={1.5 + index * 4}
          y={12.5 - height}
          width="3"
          height={height}
          rx="0.75"
          fill="currentColor"
          opacity={index < filled ? 1 : 0.3}
        />
      ))}
    </svg>
  )
}
