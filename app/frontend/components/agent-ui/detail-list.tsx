/* What a tool was given, one argument per line. The name keeps its own column, and a long value such as a command
 * wraps under itself rather than into the name. */
export type Detail = { label: string; meta: string };

export default function DetailList({ details, className = "" }: { details: Detail[]; className?: string }) {
  return (
    <dl className={`grid grid-cols-[minmax(3.5rem,auto)_minmax(0,1fr)] gap-x-4 gap-y-1.5 ${className}`}>
      {details.map((detail, index) => (
        <div key={`${detail.label}:${index}`} className="contents">
          <dt className="text-[12px] leading-5 text-ink-2">{detail.label}</dt>
          <dd className="m-0 font-mono text-[11.5px] leading-5 text-ink-3 tabular-nums whitespace-pre-wrap [overflow-wrap:anywhere]">
            {detail.meta}
          </dd>
        </div>
      ))}
    </dl>
  );
}
