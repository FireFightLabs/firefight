import { useState } from "react";
import { router } from "@inertiajs/react";

import type { Integration } from "@/types/serializers";
import { markToolReadIntegrationPath } from "@/lib/routes";
import { Blocked } from "@/components/blocked-tooltip";
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog";

type ReadMark = NonNullable<Integration["tools"][number]["readMark"]>;

// On a server Firefight cannot know, an admin marks a tool that only reads, so it is called like any read: without
// asking, outside approval rules, and by investigations and watches. Either way is confirmed with what it does.
export function ToolReadMark({
  integrationId,
  toolId,
  toolName,
  mark,
}: {
  integrationId: string;
  toolId: string;
  toolName: string;
  mark: ReadMark;
}) {
  const [confirming, setConfirming] = useState(false);
  const label = mark.marked ? "Unmark as read" : "Mark as read";

  function ask() {
    setConfirming(true);
  }

  function stopConfirming() {
    setConfirming(false);
  }

  function confirm() {
    router.patch(
      markToolReadIntegrationPath(integrationId),
      { tool_id: toolId, read: !mark.marked },
      { preserveScroll: true, onFinish: stopConfirming },
    );
  }

  return (
    <>
      <Blocked reason={mark.blockedReason ?? undefined} side="top">
        <button
          type="button"
          onClick={ask}
          disabled={mark.blockedReason !== null}
          className="text-muted-foreground hover:text-foreground text-xs disabled:pointer-events-none disabled:opacity-40"
        >
          {label}
        </button>
      </Blocked>
      <ConfirmDeleteDialog
        open={confirming}
        title={mark.marked ? `Stop treating ${toolName} as a read?` : `Mark ${toolName} as a read?`}
        description={mark.words}
        confirmLabel={label}
        confirmVariant="default"
        onConfirm={confirm}
        onCancel={stopConfirming}
      />
    </>
  );
}
