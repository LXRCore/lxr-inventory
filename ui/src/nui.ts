/* NUI plumbing shared by every LXR bundle: messages in, callbacks out, locale, mock at boot. */
export type Msg = { action?: string; [k: string]: any };
type Handler = (m: Msg) => void;
const handlers = new Set<Handler>();

export const RESOURCE = (typeof (window as any).GetParentResourceName === 'function') ? (window as any).GetParentResourceName() : 'lxr-inventory';

/* messages that arrive before the first handler mounts (the game posts 'open' right after the page loads) are kept and replayed */
const early: Msg[] = [];
export function onMessage(fn: Handler) {
  handlers.add(fn);
  if (early.length) { const q = early.splice(0); q.forEach((m) => fn(m)); }
  return () => { handlers.delete(fn); };
}
window.addEventListener('message', (e) => { const m = (e.data || {}) as Msg; if (handlers.size === 0) { early.push(m); return; } handlers.forEach((h) => h(m)); });

export async function post<T = any>(name: string, body?: unknown): Promise<T> {
  try {
    const r = await fetch(`https://${RESOURCE}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body ?? {}) });
    return (await r.json()) as T;
  } catch { return { ok: false } as unknown as T; }
}

/* brand theme + language class, the same on every bundle */
export function applyChrome(m: Msg) {
  if (m.brand && m.brand.theme) document.documentElement.dataset.theme = m.brand.theme;
  if (m.lang) document.body.classList.toggle('lang-ka', m.lang === 'ka');
}

export function makeT(locale: Record<string, string>) {
  return (k: string, vars?: Record<string, string | number>) => {
    let s = locale[k] ?? k.split('.').pop()!.replace(/_/g, ' ');
    if (vars) for (const v in vars) s = s.replace('%{' + v + '}', String(vars[v]));
    return s;
  };
}

export const money = (n: number) => '$' + (Math.round((Number(n) || 0) * 100) / 100).toFixed(2);
export const pad = (i: number) => String(i).padStart(2, '0');

/* screenshot pages set window.__LXR_MOCK__ before the bundle loads */
export function bootMock() {
  const m = (window as any).__LXR_MOCK__;
  if (m) setTimeout(() => window.postMessage(m, '*'), 0);
}
