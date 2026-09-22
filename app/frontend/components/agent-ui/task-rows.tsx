"use client";

import { useState } from "react";
import { AGENT_STEP_STATUSES } from "@/lib/generated/constants";

/* ─────────────────────────────────────────────────────────
 * TASK ROWS
 *
 * One card per thing the agent did. Rows enter staggered (80ms apart) and
 * each opens to show what the tool was given.
 * ───────────────────────────────────────────────────────── */

function SpinnerRing({ active, children }: { active?: boolean; children?: React.ReactNode }) {
  const size = 24, stroke = 2;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return (
    <span className="relative inline-flex shrink-0 items-center justify-center" style={{ width: size, height: size }}>
      <svg
        width={size} height={size} className="absolute inset-0"
        style={active ? { animation: "spin 1.1s linear infinite" } : undefined}
      >
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--line)" strokeWidth={stroke} />
        {active && (
          <circle
            cx={size / 2} cy={size / 2} r={r} fill="none"
            stroke="var(--ink-3)" strokeWidth={stroke} strokeLinecap="round"
            strokeDasharray={`${c * 0.28} ${c * 0.72}`}
          />
        )}
      </svg>
      <span className="relative text-[10.5px] font-semibold tabular-nums text-ink">{children}</span>
    </span>
  );
}

function Badge({ tone, children }: { tone: "red" | "green" | "muted"; children: React.ReactNode }) {
  return (
    <span
      className={`flex size-5.5 shrink-0 items-center justify-center rounded-full text-white
        ${tone === "red" ? "bg-red" : tone === "muted" ? "bg-ink-3" : "bg-green"}`}
      style={{ animation: "pop-in 300ms cubic-bezier(0.23,1,0.32,1) both" }}
    >
      {children}
    </span>
  );
}

const XIcon = (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.5" strokeLinecap="round"><path d="M18 6L6 18M6 6l12 12" /></svg>
);
const CheckIcon = (
  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round"><path d="M20 6L9 17l-5-5" /></svg>
);
const PauseIcon = (
  <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.5" strokeLinecap="round"><path d="M9 6v12M15 6v12" /></svg>
);

/* One detail line shown when a task row is expanded. */
export type TaskDetail = { label: string; meta: string };

// The same words the server uses for a step, so the two cannot drift apart.
export type TaskRowStatus = (typeof AGENT_STEP_STATUSES)[keyof typeof AGENT_STEP_STATUSES];

/* A single task row.
 *  - "done"      → green check badge + completed pill
 *  - "running"   → active spinner showing `step`, no pill
 *  - "waiting"   → muted pause badge + waiting pill, for a step paused on a person
 *  - "cancelled" → muted cross badge + cancelled pill, for a step the person turned down
 *  - "failed"    → red cross badge + failed pill, for a tool that refused or errored
 */
export type TaskRow = {
  key: string;
  label: string;
  amount: string;
  status: TaskRowStatus;
  step?: number;
  details: TaskDetail[];
};

export type TaskRowsLabels = {
  completed: string;
  failed: string;
  waiting: string;
  cancelled: string;
};

const DEFAULT_LABELS: TaskRowsLabels = {
  completed: "Completed",
  failed: "Failed",
  waiting: "Waiting",
  cancelled: "Cancelled",
};


export default function TaskRows({
  variant = "Capsules",
  rows,
  labels,
  className,
  onToggleRow,
}: {
  variant?: string;
  rows: TaskRow[];
  labels?: Partial<TaskRowsLabels>;
  className?: string;
  onToggleRow?: (key: string, open: boolean) => void;
}) {
  const [manualOpen, setManualOpen] = useState<Record<string, boolean>>({});
  const copy = { ...DEFAULT_LABELS, ...labels };

  const badgeFor = (row: TaskRow) => {
    if (row.status === AGENT_STEP_STATUSES.DONE) return <Badge tone="green">{CheckIcon}</Badge>;
    if (row.status === AGENT_STEP_STATUSES.RUNNING) return <SpinnerRing active>{row.step}</SpinnerRing>;
    if (row.status === AGENT_STEP_STATUSES.WAITING) return <Badge tone="muted">{PauseIcon}</Badge>;
    if (row.status === AGENT_STEP_STATUSES.CANCELLED) return <Badge tone="muted">{XIcon}</Badge>;
    return <Badge tone="red">{XIcon}</Badge>;
  };

  const pillFor = (row: TaskRow) => {
    if (row.status === AGENT_STEP_STATUSES.DONE)
      return (
        <span className="inline-flex h-5.5 items-center rounded-full bg-green-tint px-2 text-[11.5px] font-medium text-green">
          {copy.completed}
        </span>
      );
    if (row.status === AGENT_STEP_STATUSES.RUNNING) return null;
    if (row.status === AGENT_STEP_STATUSES.WAITING || row.status === AGENT_STEP_STATUSES.CANCELLED)
      return (
        <span className="inline-flex h-5.5 items-center rounded-full bg-hover-2 px-2 text-[11.5px] font-medium text-ink-2">
          {row.status === AGENT_STEP_STATUSES.WAITING ? copy.waiting : copy.cancelled}
        </span>
      );
    return (
      <span className="inline-flex h-5.5 items-center rounded-full bg-red-tint px-2 text-[11.5px] font-medium text-red" style={{ animation: "fade-in 200ms ease-out both" }}>
        {copy.failed}
      </span>
    );
  };

  const list = variant === "List";
  return (
    <div
      className={`flex w-full max-w-110 flex-col ${
        list ? "gap-0 self-start overflow-hidden rounded-card bg-surface shadow-card" : "gap-2"
      }${className ? ` ${className}` : ""}`}
    >
      {rows.map((row, i) => {
        const open = manualOpen[row.key] ?? false;
        return (
          <div
            key={row.key}
            className={`self-stretch overflow-hidden transition-[border-radius,background-color] duration-300 hover:bg-inset ${
              list ? "border-b border-line last:border-0" : "bg-surface shadow-card"
            }`}
            style={{
              borderRadius: list ? 0 : open ? 14 : 22,
              animation: `fade-up 450ms cubic-bezier(0.23,1,0.32,1) ${i * 80}ms both`,
            }}
          >
            <button
              type="button"
              aria-expanded={open}
              onClick={() => {
                setManualOpen((current) => ({ ...current, [row.key]: !open }));
                onToggleRow?.(row.key, !open);
              }}
              className="flex h-11 w-full items-center gap-2.5 px-2.5 text-left"
            >
              <span className="flex size-6 shrink-0 items-center justify-center">
                {badgeFor(row)}
              </span>
              <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-ink">
                {row.label}
              </span>
              <span className="text-[12.5px] text-ink-2 tabular-nums">{row.amount}</span>
              {pillFor(row)}
              <span
                aria-hidden="true"
                className="-ml-2 flex size-7 shrink-0 items-center justify-center rounded-full text-ink-3"
              >
                <svg
                  width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"
                  className="transition-transform duration-300"
                  style={{ transform: open ? "rotate(180deg)" : "rotate(0)" }}
                >
                  <path d="M6 9l6 6 6-6" />
                </svg>
              </span>
            </button>

            {/* dropdown detail — same expandable grammar as Chain of Thought */}
            <div
              className="grid transition-[grid-template-rows,opacity] duration-300"
                style={{
                  gridTemplateRows: open ? "1fr" : "0fr",
                  opacity: open ? 1 : 0,
                  transitionTimingFunction: "cubic-bezier(0.23, 1, 0.32, 1)",
                }}
              >
                <div className="overflow-hidden">
                  <div className="mb-2.5 grid grid-cols-[24px_1fr] gap-2.5 px-2.5">
                    <span aria-hidden className="mx-auto h-full w-px bg-line" />
                    <div className="flex flex-col gap-1.5">
                      {row.details.map((d, j) => (
                        <div
                          key={d.label}
                          className="flex items-center justify-between"
                          style={
                            open
                              ? { animation: `fade-up 300ms cubic-bezier(0.23,1,0.32,1) ${120 + j * 100}ms both` }
                              : undefined
                          }
                        >
                          <span className="text-[12px] text-ink-2">{d.label}</span>
                          <span className="font-mono text-[11.5px] text-ink-3 tabular-nums">
                            {d.meta}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              </div>
          </div>
        );
      })}
    </div>
  );
}
