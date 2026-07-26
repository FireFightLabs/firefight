export function ProviderMark({ mark, color, size = 40 }: { mark: string; color: string; size?: number }) {
  return (
    <div
      className="flex flex-none items-center justify-center rounded-lg font-bold text-white"
      style={{ width: size, height: size, backgroundColor: color, fontSize: size * 0.32 }}
      aria-hidden="true"
    >
      {mark}
    </div>
  )
}
