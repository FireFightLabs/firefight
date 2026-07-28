import { ErrorPage } from "@/pages/errors/components/error-page";

export default function ServerError({ signedIn }: { signedIn: boolean }) {
  return (
    <ErrorPage
      code="500"
      title="Something went wrong"
      description="An unexpected error happened on our side. Nothing you did caused it, so please try again in a moment."
      signedIn={signedIn}
    />
  );
}
