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
      variant="default"
      className={cn(
        "h-11 w-full cursor-pointer justify-center gap-3 font-medium active:translate-y-px",
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
