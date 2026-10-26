import { notFound } from "next/navigation";
import { KeywordDetailView } from "@/views/keyword-detail";

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^\d+$/.test(id)) notFound();
  return <KeywordDetailView id={Number(id)} />;
}
