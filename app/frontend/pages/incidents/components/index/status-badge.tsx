export function StatusBadge({ name, color }: { name: string; color: string }) {
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-medium tracking-wide"
      style={{
        backgroundColor: `color-mix(in srgb, ${color} 15%, transparent)`,
        color: `color-mix(in srgb, ${color} 75%, var(--foreground))`,
        borderColor: `color-mix(in srgb, ${color} 38%, transparent)`,
      }}
    >
      <span className="size-1.5 rounded-full" style={{ backgroundColor: color }} />
      {name}
    </span>
  )
}
