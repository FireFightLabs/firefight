import { Button } from "@/components/ui/button";
import { signInWithSlackPath } from "@/lib/routes";

export function SlackAuthButton() {
  return (
    <Button
      asChild
      variant="outline"
      className="h-11 w-full max-w-[320px] justify-center gap-3 bg-card font-medium shadow-[0_0_16px_rgba(115,211,238,0.15),0_0_4px_rgba(115,211,238,0.3)] transition-[box-shadow,transform] hover:bg-card hover:shadow-[0_0_24px_rgba(115,211,238,0.4),0_0_8px_rgba(115,211,238,0.55)] active:translate-y-px"
      style={{
        borderColor: "rgba(115,211,238,0.45)",
      }}
    >
      <a href={signInWithSlackPath()}>
        <SlackLogo className="size-[18px] shrink-0" />
        <span>Continue with Slack</span>
      </a>
    </Button>
  );
}

function SlackLogo({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 122.8 122.8"
      className={className}
      aria-hidden="true"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M25.8 77.6a12.9 12.9 0 1 1-12.9-12.9h12.9zm6.5 0a12.9 12.9 0 0 1 25.8 0v32.3a12.9 12.9 0 0 1-25.8 0z"
        fill="#E01E5A"
      />
      <path
        d="M45.2 25.8a12.9 12.9 0 1 1 12.9-12.9v12.9zm0 6.5a12.9 12.9 0 0 1 0 25.8H12.9a12.9 12.9 0 0 1 0-25.8z"
        fill="#36C5F0"
      />
      <path
        d="M97 45.2a12.9 12.9 0 1 1 12.9 12.9H97zm-6.5 0a12.9 12.9 0 0 1-25.8 0V12.9a12.9 12.9 0 0 1 25.8 0z"
        fill="#2EB67D"
      />
      <path
        d="M77.6 97a12.9 12.9 0 1 1-12.9 12.9V97zm0-6.5a12.9 12.9 0 0 1 0-25.8h32.3a12.9 12.9 0 0 1 0 25.8z"
        fill="#ECB22E"
      />
    </svg>
  );
}
