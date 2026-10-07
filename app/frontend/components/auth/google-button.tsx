import type { ComponentProps } from "react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { GoogleLogo } from "@/components/auth/google-logo";

interface GoogleButtonProps
  extends Omit<ComponentProps<typeof Button>, "asChild" | "variant" | "children"> {
  href: string;
  label: string;
}

export function GoogleButton({ href, label, className, ...props }: GoogleButtonProps) {
  return (
    <Button
      asChild
      variant="outline"
      className={cn(
        "h-11 w-full cursor-pointer justify-center gap-3 font-medium active:translate-y-px",
        className,
      )}
      {...props}
    >
      <a href={href}>
        <GoogleLogo className="size-[18px] shrink-0" />
        <span>{label}</span>
      </a>
    </Button>
  );
}
