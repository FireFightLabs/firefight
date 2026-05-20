import type { ComponentProps } from "react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { SlackLogo } from "@/components/auth/slack-logo";

interface SlackButtonProps
  extends Omit<ComponentProps<typeof Button>, "asChild" | "variant" | "children"> {
  href: string;
  label: string;
}

export function SlackButton({ href, label, className, ...props }: SlackButtonProps) {
  return (
    <Button
      asChild
      variant="outline"
      className={cn(
        "h-11 w-full cursor-pointer justify-center gap-3 border-primary/45 bg-card font-medium shadow-[0_0_16px_rgba(115,211,238,0.15),0_0_4px_rgba(115,211,238,0.3)] transition-[box-shadow,transform] hover:bg-card hover:shadow-[0_0_24px_rgba(115,211,238,0.4),0_0_8px_rgba(115,211,238,0.55)] active:translate-y-px",
        className,
      )}
      {...props}
    >
      <a href={href}>
        <SlackLogo className="size-[18px] shrink-0" />
        <span>{label}</span>
      </a>
    </Button>
  );
}
