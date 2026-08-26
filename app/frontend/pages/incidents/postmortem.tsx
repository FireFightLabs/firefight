import { useCallback, useEffect, useRef, useState } from "react";
import { Head, Link, router, usePage } from "@inertiajs/react";
import {
  IconArrowLeft,
  IconCheck,
  IconAlertTriangle,
  IconClock,
  IconDotsVertical,
  IconFlame,
} from "@tabler/icons-react";

import TurndownService from "turndown";

import type { SharedProps } from "@/types";
import type { Postmortem } from "@/types/serializers";
import { PostmortemEditor } from "@/pages/incidents/components/postmortem/postmortem-editor";
import { PostmortemGeneratingSkeleton } from "@/pages/incidents/components/postmortem/postmortem-generating-skeleton";
import { RevisionsSheet } from "@/pages/incidents/components/postmortem/revisions-sheet";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Separator } from "@/components/ui/separator";
import {
  incidentPath,
  incidentPostmortemGeneratePath,
  incidentPostmortemPath,
  incidentPostmortemStartBlankPath,
  incidentPostmortemStatusPath,
} from "@/lib/routes";
import { requestJson } from "@/lib/http";

type SaveState = "idle" | "saving" | "saved" | "conflict";

interface SaveResult {
  version?: number;
  error?: string;
}

const statusLabels: Record<string, string> = {
  draft: "Draft",
  in_progress: "In progress",
  in_review: "In review",
  completed: "Completed",
};

const statusStyles: Record<string, string> = {
  draft: "bg-muted text-muted-foreground",
  in_progress: "bg-amber-500/15 text-amber-600 dark:text-amber-400",
  in_review: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  completed: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
};

interface PostmortemPageProps extends SharedProps {
  incident: { id: string; identifier: string; name: string };
  postmortem: Postmortem | null;
}

export default function PostmortemPage() {
  const { incident, postmortem } = usePage<PostmortemPageProps>().props;

  // All hooks run unconditionally, the null-postmortem branch returns after.
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined,
  );
  const [editorKey, setEditorKey] = useState(0);
  const [revisionsOpen, setRevisionsOpen] = useState(false);
  const [saveState, setSaveState] = useState<SaveState>("idle");
  const editorContentRef = useRef(postmortem?.htmlContent ?? "");
  // The version the editor's text was built from. A save that loses to
  // somebody else's rewrite is refused rather than throwing their work away.
  const versionRef = useRef(postmortem?.version ?? 0);
  const conflictedRef = useRef(false);

  const save = useCallback(async () => {
    setSaveState("saving");
    const result = await requestJson<SaveResult>(incidentPostmortemPath(incident.id), {
      method: "PATCH",
      body: { html_content: editorContentRef.current, version: versionRef.current },
    });

    // Losing means nothing was written, so the version stays where it was and
    // the editor stops trying. Adopting the version that won would let the
    // next keystroke overwrite the work this save was refused for.
    if (!result.ok) {
      conflictedRef.current = true;
      setSaveState("conflict");
      return;
    }

    versionRef.current = result.data?.version ?? versionRef.current;
    setSaveState("saved");
  }, [incident.id]);

  const handleContentUpdate = useCallback(
    (html: string) => {
      editorContentRef.current = html;
      if (conflictedRef.current) {
        return;
      }

      clearTimeout(saveTimerRef.current);
      saveTimerRef.current = setTimeout(() => {
        saveTimerRef.current = undefined;
        void save();
      }, 1500);
    },
    [save],
  );

  const handleRestore = useCallback(
    (html: string) => {
      editorContentRef.current = html;
      setEditorKey((key) => key + 1);
      void save();
    },
    [save],
  );

  const handleExportMarkdown = useCallback(() => {
    if (!postmortem) {
      return;
    }
    const turndown = new TurndownService({
      headingStyle: "atx",
      codeBlockStyle: "fenced",
    });
    const title = `# ${postmortem.title}\n\n> ${incident.identifier} — ${incident.name}\n\n`;
    const markdown = title + turndown.turndown(editorContentRef.current || "");
    const blob = new Blob([markdown], { type: "text/markdown" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `${incident.identifier}-postmortem.md`;
    link.click();
    URL.revokeObjectURL(url);
  }, [incident, postmortem]);

  useEffect(() => {
    // Uses raw fetch with keepalive instead of Inertia's router.patch so the
    // request survives page unload / tab close. Inertia's router has no
    // keepalive equivalent, the request would be cancelled on navigation.
    const flushPendingSave = () => {
      if (!saveTimerRef.current || conflictedRef.current) {
        return;
      }
      clearTimeout(saveTimerRef.current);
      saveTimerRef.current = undefined;

      void requestJson(incidentPostmortemPath(incident.id), {
        method: "PATCH",
        body: { html_content: editorContentRef.current, version: versionRef.current },
        keepalive: true,
      });
    };

    const removeListener = router.on("before", flushPendingSave);
    return () => {
      removeListener();
      flushPendingSave();
    };
  }, [incident.id]);

  useEffect(() => {
    if (saveState !== "saved") {
      return;
    }

    const timer = setTimeout(() => setSaveState("idle"), 2000);
    return () => clearTimeout(timer);
  }, [saveState]);

  function reloadPostmortem() {
    router.reload();
  }

  function retryGeneration() {
    router.post(incidentPostmortemGeneratePath(incident.id));
  }

  function startBlank() {
    router.post(incidentPostmortemStartBlankPath(incident.id));
  }

  const isGenerating = postmortem?.generationState === "generating";
  const generationFailed = postmortem?.generationState === "failed";
  useEffect(() => {
    if (!isGenerating) {
      return;
    }
    const interval = setInterval(() => {
      router.reload({ only: ["postmortem"], preserveScroll: true });
    }, 3000);
    return () => clearInterval(interval);
  }, [isGenerating]);

  const wasGeneratingRef = useRef(isGenerating);
  useEffect(() => {
    if (wasGeneratingRef.current && !isGenerating && postmortem?.htmlContent) {
      editorContentRef.current = postmortem.htmlContent;
      setEditorKey((key) => key + 1);
    }
    wasGeneratingRef.current = isGenerating;
  }, [isGenerating, postmortem?.htmlContent]);

  if (!postmortem) {
    return (
      <>
        <Head title={`Postmortem — ${incident.identifier}`} />
        <div className="flex min-h-screen items-center justify-center">
          <div className="text-center text-muted-foreground">
            <p>No postmortem has been generated for this incident yet.</p>
            <Link
              href={incidentPath(incident.id)}
              className="mt-4 inline-block text-primary hover:underline"
            >
              Back to incident
            </Link>
          </div>
        </div>
      </>
    );
  }

  if (isGenerating || generationFailed) {
    return (
      <>
        <Head title={`Postmortem — ${incident.identifier}`} />
        <div className="min-h-screen bg-background">
          <header className="sticky top-0 z-50 border-b bg-background print:hidden">
            <div className="mx-auto flex h-12 max-w-4xl items-center gap-3 px-4 lg:px-6">
              <Link
                href={incidentPath(incident.id)}
                className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
              >
                <IconArrowLeft className="size-3.5" />
                Back to incident
              </Link>
            </div>
          </header>
          {isGenerating ? (
            <PostmortemGeneratingSkeleton />
          ) : (
            <div className="mx-auto flex max-w-4xl flex-col items-center gap-4 px-4 py-24 text-center lg:px-6">
              <p className="text-base font-medium">
                Generation failed
                {postmortem?.generationError
                  ? ` (${postmortem.generationError})`
                  : ""}
                .
              </p>
              <p className="max-w-md text-sm text-muted-foreground">
                Nothing was written. You can run it again, or start a blank
                postmortem and write it yourself.
              </p>
              <div className="flex items-center gap-2">
                <Button onClick={retryGeneration}>Try again</Button>
                <Button variant="outline" onClick={startBlank}>
                  Start blank
                </Button>
              </div>
            </div>
          )}
        </div>
      </>
    );
  }

  return (
    <>
      <Head title={`Postmortem — ${incident.identifier}`} />
      <div className="min-h-screen bg-background">
        <header className="sticky top-0 z-50 border-b bg-background print:hidden">
          <div className="mx-auto flex h-12 max-w-4xl items-center gap-3 px-4 lg:px-6">
            <Link
              href={incidentPath(incident.id)}
              className="text-muted-foreground hover:text-foreground"
            >
              <IconArrowLeft className="size-4" />
            </Link>
            <Separator orientation="vertical" className="h-4" />
            <nav className="flex items-center gap-1.5 text-sm text-muted-foreground overflow-hidden">
              <IconFlame className="size-4 shrink-0 text-primary" />
              <span className="hidden sm:inline">Incidents</span>
              <span className="hidden sm:inline">›</span>
              <span className="font-medium hidden sm:inline">
                {incident.identifier}
              </span>
              <span className="hidden sm:inline">›</span>
              <span className="truncate font-medium text-foreground">
                Postmortem
              </span>
            </nav>
            <div className="ml-auto flex items-center gap-2">
              {saveState === "saved" && (
                <span className="flex items-center gap-1 text-xs text-emerald-600 dark:text-emerald-400">
                  <IconCheck className="size-3" />
                  Saved
                </span>
              )}
              {saveState === "saving" && (
                <span className="text-xs text-muted-foreground">Saving...</span>
              )}
              <Badge
                variant="secondary"
                className={`text-xs ${statusStyles[postmortem.status]}`}
              >
                {statusLabels[postmortem.status]}
              </Badge>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setRevisionsOpen(true)}
              >
                <IconClock className="size-4" />
                Revisions
              </Button>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="icon" className="size-8">
                    <IconDotsVertical className="size-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem onClick={() => window.print()}>
                    Export as PDF
                  </DropdownMenuItem>
                  <DropdownMenuItem onClick={handleExportMarkdown}>
                    Export as Markdown
                  </DropdownMenuItem>
                  <DropdownMenuSeparator />
                  {postmortem.status !== "completed" ? (
                    <DropdownMenuItem
                      onClick={() =>
                        router.patch(
                          incidentPostmortemStatusPath(incident.id),
                          { status: "completed" },
                        )
                      }
                    >
                      Mark as Completed
                    </DropdownMenuItem>
                  ) : (
                    <DropdownMenuItem
                      onClick={() =>
                        router.patch(
                          incidentPostmortemStatusPath(incident.id),
                          { status: "draft" },
                        )
                      }
                    >
                      Reopen as Draft
                    </DropdownMenuItem>
                  )}
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </div>
        </header>

        <main className="mx-auto max-w-3xl px-4 py-12 lg:px-6 print:px-0 print:py-0 print:max-w-none">
          <div className="hidden print:block mb-8">
            <h1 className="text-2xl font-bold">{postmortem.title}</h1>
            <p className="text-sm text-muted-foreground mt-1">
              {incident.identifier}: {incident.name}
            </p>
          </div>
          {saveState === "conflict" && (
            <div className="mb-4 flex flex-wrap items-center gap-3 rounded-md border border-amber-500/40 bg-amber-500/10 px-4 py-3">
              <IconAlertTriangle className="size-4 shrink-0 text-amber-600 dark:text-amber-400" />
              <p className="text-sm text-foreground">
                Somebody else changed this postmortem while you were editing, so your last change was
                not saved. Reload to see their version, or copy your text out first.
              </p>
              <Button variant="outline" size="sm" className="ml-auto" onClick={reloadPostmortem}>
                Reload
              </Button>
            </div>
          )}
          <PostmortemEditor
            key={editorKey}
            content={editorContentRef.current || undefined}
            onUpdate={handleContentUpdate}
            incidentId={incident.id}
          />
        </main>
      </div>

      <RevisionsSheet
        incidentId={incident.id}
        currentHtml={editorContentRef.current}
        open={revisionsOpen}
        onOpenChange={setRevisionsOpen}
        onRestore={handleRestore}
      />
    </>
  );
}
