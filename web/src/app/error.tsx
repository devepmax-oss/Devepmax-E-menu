'use client';

export default function ErrorPage({ unstable_retry }: { error: Error; unstable_retry: () => void }) {
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-5 px-6 text-center">
      <h1 className="m-0 text-2xl font-extrabold">Algo salió mal</h1>
      <p className="m-0 text-soft">Intenta de nuevo en un momento.</p>
      <button type="button" onClick={() => unstable_retry()} className="press cursor-pointer rounded-full border-0 bg-brand px-6 py-3 font-bold text-on-brand">
        Reintentar
      </button>
    </main>
  );
}
