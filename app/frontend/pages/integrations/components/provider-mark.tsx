export function ProviderMark({ mark, color, size = 40 }: { mark: string; color: string; size?: number }) {
  return (
    <div
      className="ring-border/60 flex flex-none items-center justify-center rounded-lg font-bold text-white shadow-sm ring-1"
      style={{ width: size, height: size, backgroundColor: color, fontSize: size * 0.3 }}
      aria-hidden="true"
    >
      {mark}
    </div>
  )
}
