export function ColorDot({ color }: { color: string }) {
  return (
    <span
      className="inline-block size-3 rounded-full ring-1 ring-foreground/10"
      style={{ backgroundColor: color }}
    />
  )
}
