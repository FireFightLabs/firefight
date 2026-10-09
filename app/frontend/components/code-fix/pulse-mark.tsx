export function PulseMark() {
  return (
    <span aria-hidden className="relative mt-[6px] ml-[3px] mr-[3px] flex size-2 shrink-0">
      <span className="absolute inline-flex size-full rounded-full bg-stage-active opacity-60 motion-safe:animate-ping" />
      <span className="relative inline-flex size-2 rounded-full bg-stage-active" />
    </span>
  )
}
