"use client";

import { useLayoutEffect, useRef, useState, type ReactNode } from "react";

import DetailList, { type Detail } from "@/components/agent-ui/detail-list";

/* ─────────────────────────────────────────────────────────
 * THINKING, an expandable agent trace
 *
 * The trace runs while the agent works, settles, and remains expandable.
 * ───────────────────────────────────────────────────────── */

export type ThinkingRowStatus = "running" | "done" | "failed" | "waiting" | "cancelled";

export type ThinkingRow = {
  /** what tells two rows with the same words apart */
  id: string;
  primary: string;
  secondary?: string;
  /** where the step got to, drawn as its mark. Without one, the last row of a working trace spins and the rest are done */
  status?: ThinkingRowStatus;
  /** what the step was given, shown under the row once it is opened */
  details?: Detail[];
};

/* the mark each status draws, so a step reads without its colour */
function RowMark({ status }: { status: ThinkingRowStatus }) {
  if (status === "running") {
    return <span className="size-3 shrink-0 rounded-full border-[1.5px] border-line-strong border-t-ink-2 motion-safe:animate-[spin_700ms_linear_infinite]" />;
  }
  const paths: Record<Exclude<ThinkingRowStatus, "running">, { path: ReactNode; stroke: string }> = {
    done: { path: <path d="M20 6L9 17l-5-5" />, stroke: "var(--ink-3)" },
    failed: { path: <path d="M18 6L6 18M6 6l12 12" />, stroke: "var(--red)" },
    waiting: { path: <path d="M9 6v12M15 6v12" />, stroke: "var(--orange)" },
    cancelled: { path: <><circle cx="12" cy="12" r="8" /><path d="M6.5 17.5l11-11" /></>, stroke: "var(--ink-3)" },
  };
  const mark = paths[status];
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={mark.stroke} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="shrink-0" aria-hidden>
      {mark.path}
    </svg>
  );
}

const STATUS_WORDS: Record<ThinkingRowStatus, string> = {
  running: "Running", done: "Done", failed: "Failed", waiting: "Waiting for you", cancelled: "Cancelled",
};

export default function ThinkingState({
  rows,
  active,
  done,
  working = false,
  open,
  icon,
}: {
  rows: ThinkingRow[];
  active: string;
  done: string;
  /** true while the agent is still working, which shimmers the header and spins the last row */
  working?: boolean;
  /** holds the trace open without spinning a row, for the gap between two steps of a live turn */
  open?: boolean;
  /** override the header glyph (defaults to the sparkle) */
  icon?: ReactNode;
}) {
  const [manualExpanded, setManualExpanded] = useState<boolean | null>(null);
  const expanded = manualExpanded ?? (open || working);
  const traceRef = useRef<HTMLDivElement>(null);
  const [lineHeight, setLineHeight] = useState(0);
  const [openRows, setOpenRows] = useState<Record<string, boolean>>({});
  /* rows already there when the trace mounts, an opened chat, appear at rest rather than fading in one by one */
  const [firstRows] = useState(() => new Set(rows.map((row) => row.id)));
  useLayoutEffect(() => {
    if (traceRef.current) setLineHeight(traceRef.current.offsetHeight);
  }, [rows.length, expanded, working, openRows]);

  function toggleRow(id: string) {
    setOpenRows((current) => ({ ...current, [id]: !current[id] }));
  }

  function toggle() {
    setManualExpanded((current) => !(current ?? (open || working)));
  }

  return (
    <div className="flex w-full max-w-2xl flex-col">
      {/* header */}
      <button
        type="button"
        aria-expanded={expanded}
        onClick={toggle}
        className="-mx-1.5 flex w-fit items-center gap-2 rounded-control px-1.5 py-1
          transition-colors duration-100 hover:bg-hover-2"
      >
        {icon ? (
          <span className="flex shrink-0 transition-colors duration-200" style={{ color: working ? "var(--ink-2)" : "var(--ink-3)" }}>
            {icon}
          </span>
        ) : (
          <svg width="16" height="16" viewBox="0 0 24 24" fill={working ? "var(--ink-2)" : "var(--ink-3)"}>
            <path d="M12 2l2.4 7.2L22 12l-7.6 2.8L12 22l-2.4-7.2L2 12l7.6-2.8z" />
          </svg>
        )}
        <span role="status" className="contents">
          {working ? (
            <span
              className="bg-clip-text text-[13px] font-medium whitespace-nowrap text-transparent"
              style={{
                backgroundImage:
                  "linear-gradient(90deg, var(--ink-3) 35%, var(--ink) 50%, var(--ink-3) 65%)",
                backgroundSize: "200% 100%",
                animation: "shimmer-text 1.4s linear infinite",
              }}
            >
              {active}
            </span>
          ) : (
            <span
              className="text-[13px] font-medium whitespace-nowrap text-ink-2"
              style={{ animation: "fade-in 350ms ease-out both" }}
            >
              {done}
            </span>
          )}
        </span>
        <svg
          width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--ink-3)" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"
          className="transition-transform duration-300"
          style={{ transform: expanded ? "rotate(180deg)" : "rotate(0)" }}
        >
          <path d="M6 9l6 6 6-6" />
        </svg>
      </button>

      {/* expandable trace */}
      <div
        className="grid transition-[grid-template-rows,opacity] duration-400"
        style={{
          gridTemplateRows: expanded ? "1fr" : "0fr",
          opacity: expanded ? 1 : 0,
          transitionTimingFunction: "cubic-bezier(0.23, 1, 0.32, 1)",
        }}
      >
        <div className="overflow-hidden">
          <div className="relative mt-1 ml-[5px] pl-4">
            <span
              aria-hidden
              className="absolute left-[3px] w-px bg-line"
              style={{ top: -8, height: lineHeight ? lineHeight - 2 : 0, transition: "height 500ms cubic-bezier(0.23,1,0.32,1)" }}
            />
            <div ref={traceRef} className="flex flex-col gap-1 py-1">
            {rows.map((row, i) => {
              const status = row.status ?? (i < rows.length - 1 || !working ? "done" : "running");
              const opened = Boolean(openRows[row.id]);
              const expandable = Boolean(row.details?.length);
              const entrance = firstRows.has(row.id) ? undefined : "fade-up 320ms cubic-bezier(0.23,1,0.32,1) both";
              const line = (
                <>
                  <RowMark status={status} />
                  <span className="sr-only">{STATUS_WORDS[status]}</span>
                  <span className="shrink-0 text-[12.5px] font-medium text-ink">{row.primary}</span>
                  {row.secondary && <span className="min-w-0 truncate text-[12px] text-ink-3" title={row.secondary}>{row.secondary}</span>}
                  {expandable && (
                    <svg
                      width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="var(--ink-3)" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"
                      className="ml-auto shrink-0 opacity-0 transition-[opacity,transform] duration-150 group-hover/row:opacity-100 group-focus-visible/row:opacity-100"
                      style={{ transform: opened ? "rotate(180deg)" : "rotate(0)", opacity: opened ? 1 : undefined }}
                      aria-hidden
                    >
                      <path d="M6 9l6 6 6-6" />
                    </svg>
                  )}
                </>
              );
              return (
                <div key={row.id} className="flex flex-col" style={{ animation: entrance }}>
                  {expandable ? (
                    <button
                      type="button"
                      aria-expanded={opened}
                      onClick={() => toggleRow(row.id)}
                      className="group/row flex min-h-7 w-full min-w-0 items-center gap-2 rounded-[6px] px-1.5 py-0.5 text-left transition-colors duration-150 hover:bg-hover"
                    >
                      {line}
                    </button>
                  ) : (
                    <div className="flex min-h-7 w-full min-w-0 items-center gap-2 rounded-[6px] px-1.5 py-0.5">{line}</div>
                  )}
                  {expandable && opened && row.details && <DetailList details={row.details} className="mt-1 mb-1.5 ml-7" />}
                </div>
              );
            })}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
