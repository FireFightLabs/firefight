"use client";

import { useEffect, useLayoutEffect, useRef, useState } from "react";


/* ─────────────────────────────────────────────────────────
 * PROMPT BAR
 * A composer with real controls: attach, @ data sources,
 * / commands, a model picker, dictation, and send.
 * Type @ or / to open the menus. ↑↓ and Enter pick.
 * ───────────────────────────────────────────────────────── */

function Icon({ children, size = 15, strokeWidth = 1.8 }: { children: React.ReactNode; size?: number; strokeWidth?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {children}
    </svg>
  );
}

const GLYPHS: Record<string, React.ReactNode> = {
  clip: <path d="m21.4 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48" />,
  chart: <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />,
  layers: <g><path d="M12 2 2 7l10 5 10-5-10-5z" /><path d="M2 17l10 5 10-5M2 12l10 5 10-5" /></g>,
  globe: <g><circle cx="12" cy="12" r="10" /><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" /></g>,
};

type Source = {
  key: string;
  name: string;
  desc: string;
  glyph?: string;
  attach?: boolean;
  connect?: boolean;
};

const MODELS = [
  { key: "sprinkles-5", name: "Sprinkles 5", tag: "Flagship" },
  { key: "vanilla-1", name: "Vanilla 1", tag: "Basic" },
  { key: "freezer-burn", name: "Freezer Burn 0.4", tag: "Stale" },
];

/* The row the + menu leads with when the caller takes files. */
const ATTACH_ROW: Source = { key: "attach-files", name: "Attach files", desc: "Images, PDFs and text files", glyph: "clip", attach: true };

/* A file in the composer, as the caller tracks its upload. */
export type PromptAttachment = {
  key: string;
  name: string;
  size: string;
  previewUrl: string | null;
  /* 0 to 1 while it uploads */
  progress: number;
  uploading: boolean;
  error: string | null;
  note: string | null;
};

const DICTATION = "Compare pistachio weekends to last summer";

/* the last @word or /word being typed, if any */
function parseToken(draft: string): { kind: "at" | "slash"; query: string; start: number } | null {
  const match = /(^|\s)([@/])([\w-]*)$/.exec(draft);
  if (!match) return null;
  return {
    kind: match[2] === "@" ? "at" : "slash",
    query: match[3].toLowerCase(),
    start: match.index + match[1].length,
  };
}

export default function PromptBar({
  tall = false,
  placeholder,
  onSend,
  sources,
  commands,
  modelPicker = true,
  dictation = true,
  onStop,
  onSourceSearch,
  sourceHint = "Type to search sources & files",
  initialDraft = "",
  autoFocus = false,
  attachments,
}: {
  /** hero sizing: a multi-line input with controls on their own row */
  tall?: boolean;
  placeholder?: string;
  onSend?: (text: string) => void;
  /** what @ offers */
  sources: Source[];
  /** what / offers */
  commands: { key: string; name: string; desc: string }[];
  /** controls with nothing behind them yet are off rather than shown and dead */
  modelPicker?: boolean;
  dictation?: boolean;
  /** while something is running and nothing is typed, the send button stops it instead */
  onStop?: () => void;
  /** @ asks the caller as the person types, and the caller answers through sources, unfiltered here */
  onSourceSearch?: (query: string) => void;
  /** the line under the @ menu, naming what @ finds */
  sourceHint?: string;
  /** what the input holds when it mounts, so a caller can hand it a question to finish */
  initialDraft?: string;
  /** put the caret in the input on mount, at the end of the draft */
  autoFocus?: boolean;
  /** files the caller uploads as they are added, through the + menu, drag and drop or paste. Off when not given */
  attachments?: {
    items: PromptAttachment[];
    accept: string;
    /** a line under the chips, such as how many files may go */
    notice: string | null;
    /** nothing is uploading or failed, so the message can go */
    sendable: boolean;
    onAdd: (files: File[]) => void;
    onRemove: (key: string) => void;
  };
}) {
  const [draft, setDraft] = useState(initialDraft);
  const [dismissed, setDismissed] = useState(false);
  const [plusOpen, setPlusOpen] = useState(false);
  const [modelOpen, setModelOpen] = useState(false);
  const [model, setModel] = useState(MODELS[1]);
  const [dragging, setDragging] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const attached = attachments?.items ?? [];
  const [connected, setConnected] = useState(false);
  const [active, setActive] = useState(0);
  const [listening, setListening] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const wide = expanded || tall;
  const [rowBox, setRowBox] = useState<{ top: number; height: number } | null>(null);
  const [engaged, setEngaged] = useState(false);
  const [modelBox, setModelBox] = useState<{ top: number; height: number } | null>(null);
  const [modelHovered, setModelHovered] = useState<number | null>(null);
  const [modelMenuLeft, setModelMenuLeft] = useState(0);
  const [modelMenuBottom, setModelMenuBottom] = useState(0);
  const composerAnchorRef = useRef<HTMLDivElement>(null);
  const controlsRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const measureRef = useRef<HTMLSpanElement>(null);
  const modelRef = useRef<HTMLButtonElement>(null);
  const rowRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const modelRowRefs = useRef<(HTMLButtonElement | null)[]>([]);

  const token = dismissed ? null : parseToken(draft);
  // A menu with nothing in it does not open, so / stays inert until there are commands to show.
  const offered = token?.kind === "slash" ? commands.length > 0 : sources.length > 0 || Boolean(onSourceSearch);
  const menu: "at" | "slash" | null = plusOpen ? "at" : (offered ? token?.kind ?? null : null);
  const query = plusOpen ? "" : token?.query ?? "";

  const offeredSources = plusOpen && attachments ? [ATTACH_ROW, ...sources] : sources;
  const rows: { key: string; name: string; desc: string }[] =
    menu === "at"
      ? onSourceSearch ? offeredSources : offeredSources.filter((s) => s.attach || s.name.toLowerCase().includes(query))
      : menu === "slash"
        ? commands.filter((c) => c.name.slice(1).startsWith(query))
        : [];

  useEffect(() => {
    setActive(0);
    setEngaged(false);
    if (menu === "at") onSourceSearch?.(query);
  }, [menu, query, onSourceSearch]);

  /* a single highlight glides to the active row instead of each row
   * toggling its own background, matching the gliding pill in the nav */
  useLayoutEffect(() => {
    const target = rowRefs.current[active];
    if (target) setRowBox({ top: target.offsetTop, height: target.offsetHeight });
  }, [menu, query, active, connected, rows.length]);

  /* same gliding highlight in the model menu, floating to the hovered
   * row, falling back to the currently-selected model */
  const modelIndex = MODELS.findIndex((m) => m.key === model.key);
  useLayoutEffect(() => {
    if (!modelOpen) return;
    const target = modelRowRefs.current[modelHovered ?? modelIndex];
    if (target) setModelBox({ top: target.offsetTop, height: target.offsetHeight });
  }, [modelOpen, modelHovered, modelIndex]);

  /* The menu is outside the clipped composer, so align it to the model
   * trigger by measurement instead of pinning it to the far-right edge. */
  useLayoutEffect(() => {
    if (!modelOpen || !composerAnchorRef.current || !modelRef.current) return;
    const anchorRect = composerAnchorRef.current.getBoundingClientRect();
    const triggerRect = modelRef.current.getBoundingClientRect();
    setModelMenuLeft(Math.max(0, Math.min(triggerRect.left - anchorRect.left, anchorRect.width - 176)));
    setModelMenuBottom(anchorRect.bottom - triggerRect.top + 8);
  }, [modelOpen, wide, model.name]);

  useEffect(() => {
    if (!modelOpen) setModelHovered(null);
  }, [modelOpen]);

  /* focus once asked to, with the caret after whatever the input was handed */
  useEffect(() => {
    if (!autoFocus || !inputRef.current) return;
    const input = inputRef.current;
    input.focus();
    input.setSelectionRange(input.value.length, input.value.length);
  }, [autoFocus]);

  /* Their rainbow sweep played on model change through a WebGL dependency. Neither the sweep nor
     the model picker is vendored, so this is where it was. */
  const celebrate = () => {};

  const selectModel = (next: (typeof MODELS)[number]) => {
    setModel(next);
    setModelOpen(false);
    if (next.key === "sprinkles-5") celebrate();
  };

  /* dictation resolves after a beat, like a real transcript landing */
  useEffect(() => {
    if (!listening) return;
    const t = setTimeout(() => {
      setDraft((current) => (current ? `${current.trimEnd()} ${DICTATION}` : DICTATION));
      setListening(false);
      inputRef.current?.focus();
    }, 2200);
    return () => clearTimeout(t);
  }, [listening]);

  /* Move wrapped text above the controls, then grow to a compact maximum. */
  useLayoutEffect(() => {
    const input = inputRef.current;
    const controls = controlsRef.current;
    const measure = measureRef.current;
    if (!input || !controls || !measure) return;

    // The model picker is optional, and a hidden one takes no room on the row.
    const fixedControlsWidth = 28 * 3 + (modelRef.current?.offsetWidth ?? 0);
    const inlineGaps = 4 * 4;
    const inlineInputWidth = controls.clientWidth - fixedControlsWidth - inlineGaps;
    const needsFullWidth = draft.includes("\n") || measure.offsetWidth + 8 > inlineInputWidth;
    if (needsFullWidth !== expanded) {
      setExpanded(needsFullWidth);
    }

    const minHeight = 28;
    const maxHeight = 100;
    input.style.height = "0px";
    const contentHeight = input.scrollHeight;
    input.style.height = `${Math.min(Math.max(contentHeight, minHeight), maxHeight)}px`;
    input.style.overflowY = contentHeight > maxHeight ? "auto" : "hidden";
  }, [draft, expanded]);

  /* clicking anywhere outside the composer closes the open menus */
  useEffect(() => {
    if (!modelOpen && !plusOpen) return;
    const close = (event: PointerEvent) => {
      if (!(event.target as Element).closest("[data-promptbar]")) {
        setModelOpen(false);
        setPlusOpen(false);
      }
    };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [modelOpen, plusOpen]);

  const closeMenus = () => {
    setPlusOpen(false);
    setModelOpen(false);
  };

  const pick = (row: { key: string; name: string }) => {
    if (row.key === ATTACH_ROW.key) {
      fileInputRef.current?.click();
      setPlusOpen(false);
      return;
    }
    if (menu === "at") {
      setDraft(`${token ? draft.slice(0, token.start) : draft}@${row.name} `);
    } else {
      setDraft(`${token ? draft.slice(0, token.start) : draft}${row.name} `);
    }
    setPlusOpen(false);
    setDismissed(false);
    inputRef.current?.focus();
  };

  const hasContent = draft.trim().length > 0 || attached.length > 0;
  const canSend = hasContent && (attachments?.sendable ?? true);
  const stops = onStop !== undefined && !hasContent;
  const send = () => {
    if (!canSend) return;
    onSend?.(draft.trim());
    setDraft("");
    closeMenus();
  };

  const takeFiles = (files: FileList | null) => {
    const list = Array.from(files ?? []);
    if (list.length > 0) attachments?.onAdd(list);
  };

  /* only a drag that carries files lights the composer up */
  const carriesFiles = (event: React.DragEvent) => Boolean(attachments) && event.dataTransfer.types.includes("Files");
  const dragOver = (event: React.DragEvent) => {
    if (!carriesFiles(event)) return;
    event.preventDefault();
    setDragging(true);
  };
  const dragLeave = (event: React.DragEvent) => {
    if (event.currentTarget.contains(event.relatedTarget as Node | null)) return;
    setDragging(false);
  };
  const drop = (event: React.DragEvent) => {
    if (!carriesFiles(event)) return;
    event.preventDefault();
    setDragging(false);
    takeFiles(event.dataTransfer.files);
    inputRef.current?.focus();
  };

  /* a pasted screenshot is attached, and pasted text still lands in the input */
  const paste = (event: React.ClipboardEvent<HTMLTextAreaElement>) => {
    if (!attachments || event.clipboardData.files.length === 0) return;
    takeFiles(event.clipboardData.files);
    if (!event.clipboardData.types.includes("text/plain")) event.preventDefault();
  };

  return (
    <div
      data-promptbar
      className="w-full"
    >
      {/* composer is the anchor, and menus grow up from its top edge */}
      <div ref={composerAnchorRef} className="relative">
      {/* ── @ / slash menu ─────────────────────────────── */}
      {menu && (
        <div
          onMouseLeave={() => setEngaged(false)}
          className="absolute inset-x-0 bottom-full z-10 mb-2 rounded-[10px] bg-surface p-1 shadow-raised"
          style={{ animation: "pop-in 180ms cubic-bezier(0.23,1,0.32,1) both", transformOrigin: "bottom center" }}
        >
          {/* single gliding highlight that appears once a row is hovered */}
          <span
            aria-hidden
            className="pointer-events-none absolute inset-x-1 rounded-[6px] bg-hover"
            style={{
              top: rowBox?.top ?? 0,
              height: rowBox?.height ?? 0,
              opacity: rowBox && engaged && rows.length > 0 ? 1 : 0,
              transition:
                "top 220ms cubic-bezier(0.23,1,0.32,1), height 220ms cubic-bezier(0.23,1,0.32,1), opacity 150ms ease",
            }}
          />
          {rows.map((row, i) => {
            const source = menu === "at" ? offeredSources.find((s) => s.key === row.key) : undefined;
            return (
              <button
                key={row.key}
                type="button"
                ref={(el) => {
                  rowRefs.current[i] = el;
                }}
                onMouseDown={(event) => event.preventDefault()}
                onMouseEnter={() => {
                  setActive(i);
                  setEngaged(true);
                }}
                onClick={() => pick(row)}
                className="relative z-10 flex h-9 w-full items-center gap-2.5 rounded-[6px] px-2 text-left"
              >
                {source && (
                  <span className="flex size-5.5 shrink-0 items-center justify-center text-ink-2">
                    <Icon size={15}>{GLYPHS[source.glyph ?? "clip"]}</Icon>
                  </span>
                )}
                <span className="shrink-0 text-[12.5px] font-medium text-ink">
                  {row.name}
                </span>
                <span className="min-w-0 flex-1 truncate text-[12px] text-ink-3">{row.desc}</span>
                {source?.connect && (
                  <span
                    role="button"
                    tabIndex={-1}
                    onClick={(event) => {
                      event.stopPropagation();
                      setConnected((current) => !current);
                    }}
                    className={`shrink-0 text-[12px] font-medium transition-colors duration-100 ${
                      connected ? "text-green" : "text-accent hover:underline"
                    }`}
                  >
                    {connected ? "Connected" : "Connect"}
                  </span>
                )}
              </button>
            );
          })}
          {rows.length === 0 && (
            <div className="flex h-9 items-center px-2 text-[12px] text-ink-3">
              No matches for “{query}”
            </div>
          )}
          <div className="mt-1 border-t border-line px-2 pt-1.5 pb-1 text-[11px] text-ink-3">
            {menu === "at" ? sourceHint : "Type to search commands"}
          </div>
        </div>
      )}

      {/* ── model menu ─────────────────────────────────── */}
      {modelOpen && (
        <div
          onMouseLeave={() => setModelHovered(null)}
          className="absolute z-10 w-44 rounded-[10px] bg-surface p-1 shadow-raised"
          style={{ left: modelMenuLeft, bottom: modelMenuBottom, animation: "pop-in 180ms cubic-bezier(0.23,1,0.32,1) both", transformOrigin: "bottom left" }}
        >
          {/* single gliding highlight that floats to the hovered or selected row */}
          <span
            aria-hidden
            className="pointer-events-none absolute inset-x-1 rounded-[6px] bg-hover"
            style={{
              top: modelBox?.top ?? 0,
              height: modelBox?.height ?? 0,
              opacity: modelBox && modelHovered !== null ? 1 : 0,
              transition:
                "top 220ms cubic-bezier(0.23,1,0.32,1), height 220ms cubic-bezier(0.23,1,0.32,1), opacity 150ms ease",
            }}
          />
          {MODELS.map((m, i) => (
            <button
              key={m.key}
              type="button"
              ref={(el) => {
                modelRowRefs.current[i] = el;
              }}
              onMouseDown={(event) => event.preventDefault()}
              onMouseEnter={() => setModelHovered(i)}
              onClick={() => {
                selectModel(m);
                inputRef.current?.focus();
              }}
              className="relative z-10 flex h-7.5 w-full items-center gap-2 rounded-[6px] px-2 text-left"
            >
              <span className="min-w-0 flex-1 truncate text-[12.5px] font-medium text-ink">{m.name}</span>
              <span className="shrink-0 text-[11px] text-ink-3">{m.tag}</span>
              <span className={`shrink-0 text-ink ${m.key === model.key ? "" : "invisible"}`}>
                <Icon size={13} strokeWidth={2.5}><path d="M20 6L9 17l-5-5" /></Icon>
              </span>
            </button>
          ))}
        </div>
      )}

      {/* ── composer ───────────────────────────────────── */}
      <div
        onDragEnter={dragOver}
        onDragOver={dragOver}
        onDragLeave={dragLeave}
        onDrop={drop}
        className={`relative isolate flex flex-col overflow-hidden border bg-surface-input transition-[border-color,border-radius] duration-150 focus-within:border-border-control ${dragging ? "border-accent" : "border-line-strong"} ${
          tall ? "gap-2.5 p-3.5" : "gap-1.5 p-1.5"
        } ${
          tall ? "rounded-[22px]" : "rounded-[14px]"
        }`}
      >
        <span
          ref={measureRef}
          aria-hidden="true"
          className="pointer-events-none absolute invisible whitespace-pre text-[13px] leading-[18px]"
        >
          {draft}
        </span>

        {attachments && (
          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept={attachments.accept}
            aria-label="Attach files"
            className="hidden"
            onChange={(event) => {
              takeFiles(event.target.files);
              event.target.value = "";
              inputRef.current?.focus();
            }}
          />
        )}

        {dragging && (
          <div className="pointer-events-none absolute inset-0 z-20 flex items-center justify-center bg-surface-input/90 text-[13px] font-medium text-ink">
            Drop files to attach
          </div>
        )}

        {attached.length > 0 && (
          <div className="flex flex-wrap gap-1.5 pt-0.5 px-0.5" aria-label="Attached files">
            {attached.map((file) => (
              <span
                key={file.key}
                title={file.error ?? file.note ?? undefined}
                className={`relative flex h-7 items-center gap-1.5 overflow-hidden bg-field py-1 pr-1 pl-1 text-[11.5px] text-ink-2 rounded-chip ${file.error ? "shadow-[0_0_0_1px_var(--red)]" : "shadow-hairline"}`}
                style={{ animation: "pop-in 200ms cubic-bezier(0.23,1,0.32,1) both" }}
              >
                {file.previewUrl ? (
                  <img src={file.previewUrl} alt="" className="size-5 shrink-0 rounded-[4px] object-cover" />
                ) : (
                  <span className="flex size-5 shrink-0 items-center justify-center text-ink-3">
                    <Icon size={12}><g><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><path d="M14 2v6h6" /></g></Icon>
                  </span>
                )}
                <span className="max-w-36 truncate text-ink">{file.name}</span>
                <span className="shrink-0 text-ink-3">
                  {file.uploading ? `${Math.round(file.progress * 100)}%` : file.size}
                </span>
                <button
                  type="button"
                  aria-label={`Remove ${file.name}`}
                  onClick={() => attachments?.onRemove(file.key)}
                  className="-my-1 flex size-6 items-center justify-center text-ink-3 transition-colors duration-100 hover:bg-line/70 hover:text-ink rounded-[5px]"
                >
                  <Icon size={10} strokeWidth={2.5}><path d="M18 6L6 18M6 6l12 12" /></Icon>
                </button>
                {file.uploading && (
                  <span
                    aria-hidden
                    className="absolute bottom-0 left-0 h-[2px] bg-accent transition-[width] duration-150"
                    style={{ width: `${Math.round(file.progress * 100)}%` }}
                  />
                )}
              </span>
            ))}
          </div>
        )}

        {(attachments?.notice || attached.some((file) => file.error || file.note)) && (
          <ul className="flex flex-col gap-0.5 px-1 text-[12px] leading-[16px]" aria-live="polite">
            {attached.map((file) => (file.error || file.note) && (
              <li key={file.key} className={file.error ? "text-red" : "text-ink-3"}>{file.error ?? file.note}</li>
            ))}
            {attachments?.notice && <li className="text-red">{attachments.notice}</li>}
          </ul>
        )}

        <div
          ref={controlsRef}
          className={`grid items-end gap-x-1 gap-y-1.5 ${
            wide
              ? "grid-cols-[28px_auto_minmax(0,1fr)_28px_28px]"
              : "grid-cols-[28px_minmax(0,1fr)_auto_28px_28px]"
          }`}
        >
          <button
            type="button"
            aria-label="Add attachments and sources"
            aria-expanded={plusOpen}
            onClick={() => {
              setModelOpen(false);
              setPlusOpen((current) => !current);
              inputRef.current?.focus();
            }}
            className={`flex size-7 shrink-0 items-center justify-center justify-self-start text-ink-3 transition-[background-color,color,transform] duration-150 hover:bg-hover hover:text-ink active:scale-[0.94] rounded-[8px] ${plusOpen ? "bg-hover text-ink" : ""} ${wide ? "col-start-1 row-start-2" : "col-start-1 row-start-1"}`}
          >
            <Icon size={16} strokeWidth={2}><path d="M12 5v14M5 12h14" /></Icon>
          </button>

          <textarea
            ref={inputRef}
            rows={1}
            value={draft}
            onChange={(event) => {
              setDraft(event.target.value);
              setDismissed(false);
              setPlusOpen(false);
            }}
            onPaste={paste}
            onKeyDown={(event) => {
              if (menu && rows.length > 0) {
                if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                  event.preventDefault();
                  setEngaged(true);
                  setActive((current) => (current + (event.key === "ArrowDown" ? 1 : rows.length - 1)) % rows.length);
                  return;
                }
                if ((event.key === "Enter" && !event.shiftKey) || event.key === "Tab") {
                  event.preventDefault();
                  pick(rows[active]);
                  return;
                }
              }
              if (event.key === "Escape") {
                setDismissed(true);
                closeMenus();
                return;
              }
              if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
                event.preventDefault();
                send();
              }
            }}
            placeholder={listening ? "Listening…" : placeholder ?? "Write a message…"}
            aria-label="Prompt"
            className={`${tall ? "min-h-[68px] px-2 py-2 text-[14px] leading-5" : "min-h-7 px-1 py-[5px] text-[13px] leading-[18px]"} min-w-0 w-full resize-none bg-transparent text-ink outline-none [overflow-wrap:anywhere] placeholder:text-ink-3 ${
              wide ? "col-span-full col-start-1 row-start-1" : "col-start-2 row-start-1"
            }`}
          />

          {/* model picker */}
          {modelPicker && (
          <button
            ref={modelRef}
            type="button"
            aria-expanded={modelOpen}
            aria-label="Choose model"
            onClick={() => {
              setPlusOpen(false);
              setModelOpen((current) => !current);
            }}
            className={`flex h-7 shrink-0 items-center gap-1 px-1.5 text-[12px] font-medium text-ink-2 transition-colors duration-150 hover:bg-hover hover:text-ink rounded-[8px] ${wide ? "col-start-2 row-start-2 justify-self-start" : "col-start-3 row-start-1"}`}
          >
            {model.name}
            <span className="text-ink-3">
              <Icon size={11} strokeWidth={2.4}><path d="M6 9l6 6 6-6" /></Icon>
            </span>
          </button>
          )}

          {/* dictation */}
          {dictation && (
          <button
            type="button"
            aria-label={listening ? "Stop dictation" : "Start dictation"}
            aria-pressed={listening}
            onClick={() => setListening((current) => !current)}
            className={`flex size-7 shrink-0 items-center justify-center transition-[background-color,color,transform] duration-150 active:scale-[0.94] rounded-[8px] ${listening ? "bg-accent-tint text-accent" : "text-ink-3 hover:bg-hover hover:text-ink"} ${wide ? "col-start-4 row-start-2" : "col-start-4 row-start-1"}`}
          >
            {listening ? (
              <span className="flex h-3.5 items-center gap-[2.5px]">
                {[0, 1, 2].map((i) => (
                  <span
                    key={i}
                    className="w-[2.5px] rounded-full bg-current"
                    style={{ height: "100%", animation: `eq-bounce 900ms ease-in-out ${i * 150}ms infinite` }}
                  />
                ))}
              </span>
            ) : (
              <Icon size={15} strokeWidth={2}><g><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z" /><path d="M19 10v2a7 7 0 0 1-14 0v-2M12 19v3" /></g></Icon>
            )}
          </button>
          )}

          {/* send, or stop while something runs and nothing is typed */}
          <button
            type="button"
            aria-label={stops ? "Stop" : "Send"}
            disabled={!canSend && !stops}
            onClick={stops ? onStop : send}
            className={`flex size-7 shrink-0 items-center justify-center transition-[background-color,color,transform] duration-200 enabled:active:scale-[0.94] rounded-[8px] ${wide ? "col-start-5 row-start-2" : "col-start-5 row-start-1"}`}
            style={{
              background: canSend || stops ? "var(--ink)" : "var(--line-strong)",
              color: canSend || stops ? "var(--surface)" : "var(--ink-2)",
            }}
          >
            {stops ? (
              <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><rect width="10" height="10" rx="2" fill="currentColor" /></svg>
            ) : (
              <Icon size={16} strokeWidth={2.4}><path d="M12 19V5M5 12l7-7 7 7" /></Icon>
            )}
          </button>
        </div>
      </div>
      </div>
    </div>
  );
}
