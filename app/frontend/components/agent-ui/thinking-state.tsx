"use client";

import { useLayoutEffect, useRef, useState, type ReactNode } from "react";

/* ─────────────────────────────────────────────────────────
 * THINKING — expandable agent trace
 *
 * The trace runs while the agent works, settles, and remains expandable.
 * ───────────────────────────────────────────────────────── */

export type ThinkingRow = {
  /** what tells two rows with the same words apart */
  id: string;
  primary: string;
  secondary?: string;
};

export default function ThinkingState({
  rows,
  active,
  done,
  working = false,
  icon,
}: {
  rows: ThinkingRow[];
  active: string;
  done: string;
  /** true while the agent is still working, which shimmers the header and spins the last row */
  working?: boolean;
  /** override the header glyph (defaults to the sparkle) */
  icon?: ReactNode;
}) {
  const [manualExpanded, setManualExpanded] = useState<boolean | null>(null);
  const expanded = manualExpanded ?? working;
  const traceRef = useRef<HTMLDivElement>(null);
  const [lineHeight, setLineHeight] = useState(0);
  useLayoutEffect(() => {
    if (traceRef.current) setLineHeight(traceRef.current.offsetHeight);
  }, [rows.length, expanded, working]);

  function toggle() {
    setManualExpanded((current) => !(current ?? working));
  }

  return (
    <div className="flex w-full max-w-95 flex-col">
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
            {rows.map((row, i) => (
              <div
                key={row.id}
                className="flex min-h-7 w-full items-center gap-2 rounded-[6px] px-1.5 py-0.5 text-left"
                style={{ animation: `fade-up 320ms cubic-bezier(0.23,1,0.32,1) ${i * 120}ms both` }}
              >
                {i < rows.length - 1 || !working ? (
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--ink-3)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
                    <path d="M20 6L9 17l-5-5" />
                  </svg>
                ) : (
                  <span className="size-3 shrink-0 rounded-full border-[1.5px] border-line-strong border-t-ink-2" style={{ animation: "spin 700ms linear infinite" }} />
                )}
                <span className="min-w-0 truncate text-[12.5px] font-medium text-ink">
                  {row.primary}
                </span>
                {row.secondary && (
                  <span className="shrink-0 text-[11.5px] text-ink-3">
                    {row.secondary}
                  </span>
                )}
              </div>
            ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
