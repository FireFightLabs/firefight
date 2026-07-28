import { ErrorPage } from "@/pages/errors/components/error-page";

export default function NotFound({ signedIn }: { signedIn: boolean }) {
  return (
    <ErrorPage
      code="404"
      title="Page not found"
      description="The page you are looking for does not exist, or it may have moved."
      signedIn={signedIn}
    />
  );
}
