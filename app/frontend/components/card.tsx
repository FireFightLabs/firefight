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
      feature: "gap-0 rounded-[14px] border-border px-8 pb-8 pt-10 shadow-none sm:px-10 sm:pb-10 sm:pt-12",
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
