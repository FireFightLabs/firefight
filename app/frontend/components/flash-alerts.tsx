import { usePage } from "@inertiajs/react";
import { IconAlertTriangle, IconCircleCheck } from "@tabler/icons-react";

import { Alert, AlertDescription } from "@/components/ui/alert";
import { cn } from "@/lib/utils";

export function FlashAlerts({ className }: { className?: string }) {
  const { flash } = usePage();

  if (!flash.notice && !flash.alert) return null;

  return (
    <div className={cn("space-y-3", className)}>
      {flash.notice ? (
        <Alert className="border-emerald-500/30 bg-emerald-500/10 text-emerald-300 [&>svg]:text-emerald-300">
          <IconCircleCheck />
          <AlertDescription className="text-emerald-300">
            {flash.notice}
          </AlertDescription>
        </Alert>
      ) : null}
      {flash.alert ? (
        <Alert variant="destructive">
          <IconAlertTriangle />
          <AlertDescription>{flash.alert}</AlertDescription>
        </Alert>
      ) : null}
    </div>
  );
}
