import Link from "next/link";

export default function NotFound() {
  return (
    <div className="py-16 text-center">
      <h1 className="text-2xl font-semibold">404</h1>
      <p className="mt-2 text-muted">This page does not exist. / 페이지를 찾을 수 없습니다.</p>
      <Link href="/" className="mt-4 inline-block text-accent underline">SearchOps</Link>
    </div>
  );
}
