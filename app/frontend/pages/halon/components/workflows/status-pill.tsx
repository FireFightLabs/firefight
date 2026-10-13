// A status in its tone, the words given, so a list and a page read it the same.
export function StatusPill({ label, tone }: { label: string; tone: string }) {
  return (
    <span className={`inline-flex w-fit items-center rounded-full border px-2 py-0.5 text-[11px] font-medium whitespace-nowrap ${tone}`}>
      {label}
    </span>
  )
}
