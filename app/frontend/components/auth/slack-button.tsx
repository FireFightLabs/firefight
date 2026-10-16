import type { ComponentProps } from "react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { AuthPostForm } from "@/components/auth/auth-post-form";
import { SlackLogo } from "@/components/auth/slack-logo";

interface SlackButtonProps
  extends Omit<ComponentProps<typeof Button>, "asChild" | "variant" | "children" | "type"> {
  href: string;
  label: string;
}

export function SlackButton({ href, label, className, ...props }: SlackButtonProps) {
  return (
    <AuthPostForm action={href} className="w-full">
      <Button
        type="submit"
        variant="default"
        className={cn(
          "h-11 w-full cursor-pointer justify-center gap-3 font-medium active:translate-y-px",
          className,
        )}
        {...props}
      >
        <SlackLogo className="size-[18px] shrink-0" />
        <span>{label}</span>
      </Button>
    </AuthPostForm>
  );
}
