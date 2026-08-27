import { cva, type VariantProps } from "class-variance-authority";
import type { ComponentProps } from "react";

import {
  Card as ShadcnCard,
  CardAction,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { cn } from "@/lib/utils";

const cardVariants = cva("", {
  variants: {
    variant: {
      default: "",
      glow: "gap-0 rounded-[14px] border-primary/30 px-8 pb-8 pt-10 shadow-[0_1px_2px_0_rgba(0,0,0,0.2),0_20px_60px_0_rgba(0,0,0,0.4),0_0px_60px_0_rgba(115,211,238,0.06)] sm:px-10 sm:pb-10 sm:pt-12",
    },
  },
  defaultVariants: { variant: "default" },
});

type CardProps = ComponentProps<typeof ShadcnCard> & VariantProps<typeof cardVariants>;

function Card({ className, variant, ...props }: CardProps) {
  return (
    <ShadcnCard
      className={cn(cardVariants({ variant }), className)}
      {...props}
    />
  );
}

export {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
};
