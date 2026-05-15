import { Button } from "@/components/ui/button";
import { signInWithSlackPath } from "@/lib/routes";
import { SlackLogo } from "@/modules/auth/components/slack-logo";

export function SlackAuthButton() {
  return (
    <Button
      asChild
      variant="outline"
      className="mx-auto h-11 w-full max-w-[320px] justify-center gap-3 border-primary/45 bg-card font-medium shadow-[0_0_16px_rgba(115,211,238,0.15),0_0_4px_rgba(115,211,238,0.3)] transition-[box-shadow,transform] hover:bg-card hover:shadow-[0_0_24px_rgba(115,211,238,0.4),0_0_8px_rgba(115,211,238,0.55)] active:translate-y-px"
    >
      <a href={signInWithSlackPath()}>
        <SlackLogo className="size-[18px] shrink-0" />
        <span>Continue with Slack</span>
      </a>
    </Button>
  );
}
