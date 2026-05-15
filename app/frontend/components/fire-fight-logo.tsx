import type { SVGAttributes } from "react";

import { cn } from "@/lib/utils";

const BRAND_COLOR = "#73D3EE";

interface FireFightLogoProps
  extends Omit<SVGAttributes<SVGSVGElement>, "color"> {
  color?: string;
}

export function FireFightLogo({
  className,
  color = BRAND_COLOR,
  ...rest
}: FireFightLogoProps) {
  return (
    <svg
      viewBox="20 20 34 39"
      fill={color}
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
      className={cn("size-9", className)}
      {...rest}
    >
      <path d="M50.8096 30.2171C52.7322 32.9637 53.8622 36.3063 53.8623 39.9134L53.8564 40.3509C53.6246 49.4995 46.1351 56.8448 36.9307 56.845L36.4941 56.8392C35.8569 56.823 35.2282 56.7705 34.6104 56.6858L36.0596 54.3177C36.3476 54.3348 36.6383 54.345 36.9307 54.345C44.9005 54.3448 51.3623 47.8833 51.3623 39.9134C51.3622 37.2371 50.632 34.7317 49.3623 32.5833L50.8096 30.2171ZM36.9307 22.9827C38.8085 22.9828 40.6147 23.2894 42.3027 23.8538L40.7695 26.0003C39.5471 25.6637 38.26 25.4827 36.9307 25.4827C28.961 25.4829 22.5003 31.9437 22.5 39.9134C22.5 42.9326 23.4275 45.735 25.0127 48.052L23.4805 50.1966C21.2976 47.3457 20 43.7813 20 39.9134C20.0003 30.563 27.5803 22.9829 36.9307 22.9827Z" />
      <path d="M23.336 59L51.2016 20L27.6572 58.4694L23.336 59Z" />
    </svg>
  );
}
