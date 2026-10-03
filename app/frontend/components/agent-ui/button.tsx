"use client";

import { ButtonHTMLAttributes } from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

/* Pill-shaped by default, the app's core button style. Explicit symmetric
 * padding (not a fixed height) so the top/bottom spacing is always equal. */
export const buttonVariants = cva(
  `inline-flex items-center justify-center font-medium select-none
   transition-[transform,background-color,color,opacity] duration-150 ease-out
   active:scale-[0.96] motion-reduce:transition-none motion-reduce:active:scale-100
   disabled:opacity-50 disabled:pointer-events-none`,
  {
    variants: {
      variant: {
        primary: "bg-primary text-primary-foreground hover:bg-[var(--btn-primary-hover)] active:bg-[var(--btn-primary-press)]",
        secondary: "bg-surface text-ink shadow-btn hover:bg-hover aria-expanded:bg-hover-2",
        ghost: "bg-hover-2 text-ink hover:bg-line-strong",
        accent: "bg-accent text-accent-ink hover:bg-[var(--lime-hover)] active:bg-[var(--lime-press)]",
        success: "bg-green text-accent-ink hover:bg-[var(--lime-hover)] active:bg-[var(--lime-press)]",
        /* transparent until hovered, for dense toolbars and action rows */
        quiet: "text-ink hover:bg-hover",
      },
      size: {
        /* compact toolbar pill with a fixed height and lighter weight */
        xs: "h-7 rounded-full px-2.5 text-[12px] font-normal leading-none gap-1",
        /* canonical action pill, 27px tall with roomy sides */
        sm: "h-[27px] px-3 text-[13px] leading-none rounded-full gap-1.5",
        md: "px-4 py-[9px] text-sm leading-none rounded-full gap-2",
      },
    },
    defaultVariants: { variant: "secondary", size: "md" },
  },
);

export type ButtonVariant = NonNullable<VariantProps<typeof buttonVariants>["variant"]>;

export function Button({
  variant,
  size,
  className,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & VariantProps<typeof buttonVariants>) {
  return <button className={cn(buttonVariants({ variant, size }), className)} {...props} />;
}
