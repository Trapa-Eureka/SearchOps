import { Suspense } from "react";
import { KeywordsView } from "@/views/keywords";

export default function Page() {
  // useSearchParams (the planner's prefill) needs a Suspense boundary.
  return (
    <Suspense fallback={null}>
      <KeywordsView />
    </Suspense>
  );
}
