/* LXR-INVENTORY — the satchel | © 2026 iBoss21 / LXRCore
   Messages: open { player, other, locale, lang, hotbar, brand, wearing, images } · update { player?, other?, wearing? } · itembox { item, kind, amount } · close
   Callbacks: move { from, to, fromSlot, toSlot, amount } · use { slot } · give { slot, amount } · drop · sort · transfer { direction, mode } · wear { cat, hidden } · buy { slot, amount } · close */
import { useEffect, useMemo, useRef, useState, type PointerEvent as RPointerEvent } from 'react';
import { onMessage, applyChrome, makeT, post, pad, type Msg } from './nui';

type Item = { slot: number; name: string; label: string; amount: number; weight: number; info: Record<string, any>; type?: string; useable?: boolean; unique?: boolean; image?: string; description?: string; price?: number; rarity?: string; category?: string; legal?: boolean; fresh?: number | null };
type Trade = { id: number; partner: string; theirs: Item[]; theirSlots: number; money: { mine: number; theirs: number }; confirmed: { mine: boolean; theirs: boolean } };
type Container = { id: string; kind: string; label: string; slots: number; maxWeight: number; weight: number; items: Item[]; account?: string; trade?: Trade };
type Key = 'player' | 'other';
type Wear = Record<string, { worn?: boolean; hidden?: boolean }>;
type Sort = 'slot' | 'name' | 'amount' | 'weight';
type Box = { id: number; label: string; name: string; kind: string; amount: number };

const CATS: Record<string, string> = { food: 'food', drink: 'drink', alcohol: 'alcohol', medical: 'medical', herb: 'medical', weapon: 'weapon', thrown: 'weapon', ammo: 'ammo', tool: 'tool', kit: 'tool', camp: 'tool', fishing: 'tool', material: 'material', component: 'material', hunting: 'hunting', meat: 'hunting', document: 'document', key: 'document', clothing: 'clothing', personal: 'clothing' };
const CAT_ORDER = ['food', 'drink', 'alcohol', 'medical', 'weapon', 'ammo', 'tool', 'material', 'hunting', 'document', 'clothing', 'other'];
const WEAR: [string, string][] = [['hats', 'M4 14l2-8h12l2 8M2 14h20v3H2z'], ['masks', 'M4 8h16v6l-4 5H8l-4-5z'], ['eyewear', 'M2 12h4a3 3 0 0 0 6 0h0a3 3 0 0 0 6 0h4M8 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm8 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'],
  ['coats', 'M8 3l4 3 4-3 4 3v15H4V6zM12 6v15'], ['shirts_full', 'M7 3l5 2 5-2 3 4-3 2v12H7V9L4 7z'], ['vests', 'M8 3l4 4 4-4 3 3v14H5V6z'],
  ['pants', 'M6 3h12l1 18h-5l-2-9-2 9H5z'], ['boots', 'M7 3h6v9l6 4v5H7z'], ['gloves', 'M8 21V9l-2-3 2-3 2 3 2-3 2 3 2-3 2 3v12z'],
  ['neckwear', 'M12 3l4 5-4 13-4-13z'], ['gunbelts', 'M3 10h18v4H3zM10 10v4M14 10v4'], ['satchels', 'M4 8h16v12H4zM8 8V5h8v3']];
const kg = (g: number) => (Number(g || 0) / 1000).toFixed(1) + ' kg';
const money = (n: number) => '$' + (Math.round((Number(n) || 0) * 100) / 100).toFixed(2);
const catOf = (it: Item) => CATS[it.category || ''] || 'other';
let boxSeq = 0;

export function App() {
  const [C, setC] = useState<{ player: Container | null; other: Container | null }>({ player: null, other: null });
  const [open, setOpen] = useState(false);
  const [L, setL] = useState<Record<string, string>>({});
  const [hotbar, setHotbar] = useState(5);
  const [images, setImages] = useState('images/');
  const [wearing, setWearing] = useState<Wear | null>(null);
  const [wearLabels, setWearLabels] = useState<Record<string, string>>({});
  const [q, setQ] = useState('');
  const [cat, setCat] = useState('all');
  const [sort, setSort] = useState<Sort>('slot');
  const [sel, setSel] = useState<{ key: Key; slot: number } | null>(null);
  const [amount, setAmount] = useState(1);
  const [menu, setMenu] = useState<{ key: Key; slot: number; x: number; y: number } | null>(null);
  const [drag, setDrag] = useState<{ key: Key; slot: number; x: number; y: number; item: Item; n?: number } | null>(null);
  const [over, setOver] = useState<{ key: Key; slot: number } | null>(null);
  const [boxes, setBoxes] = useState<Box[]>([]);
  const t = makeT(L);
  const dragRef = useRef<typeof drag>(null);

  useEffect(() => onMessage((m: Msg) => {
    applyChrome(m);
    if (m.action === 'open') { setL(m.locale || {}); setHotbar(m.hotbar || 5); if (m.images) setImages(m.images); setWearing(m.wearing || null); if (m.wearLabels) setWearLabels(m.wearLabels); setC({ player: m.player || null, other: m.other || null }); setOpen(true); setSel(null); setMenu(null); setQ(''); setCat('all'); }
    else if (m.action === 'update') { setC((c) => ({ player: m.player !== undefined ? m.player : c.player, other: m.other !== undefined ? (m.other || null) : c.other })); if (m.wearing !== undefined) setWearing(m.wearing || null); if (m.wearLabels) setWearLabels(m.wearLabels); }
    else if (m.action === 'itembox') { const id = ++boxSeq; setBoxes((b) => [...b, { id, label: m.item?.label || m.item?.name || '', name: m.item?.name || '', kind: m.kind, amount: m.amount || 1 }]); setTimeout(() => setBoxes((b) => b.filter((x) => x.id !== id)), 3200); }
    else if (m.action === 'close') { setOpen(false); setMenu(null); setDrag(null); }
  }), []);
  useEffect(() => {
    const k = (e: KeyboardEvent) => { if (!open) return; if (e.key === 'Escape') { if (menu) setMenu(null); else post('close'); } };
    const click = () => setMenu(null);
    document.addEventListener('keydown', k); document.addEventListener('click', click);
    return () => { document.removeEventListener('keydown', k); document.removeEventListener('click', click); };
  }, [open, menu]);

  const selected = useMemo(() => sel && C[sel.key]?.items.find((i) => i.slot === sel.slot) || null, [sel, C]);
  useEffect(() => { if (selected) setAmount(Math.min(amount, selected.amount) || 1); }, [selected]);
  const cats = useMemo(() => { const set = new Set<string>(); C.player?.items.forEach((i) => set.add(catOf(i))); return CAT_ORDER.filter((c) => set.has(c)); }, [C.player]);
  const img = (it: Item | Box) => images + ((it as Item).image || it.name + '.png');

  /* ── moving things: pointer drag with a ghost, drop on a slot ── */
  const startDrag = (key: Key, it: Item) => (e: RPointerEvent) => {
    if (e.button !== 0) return;
    // shift = the whole stack, alt = half of it, otherwise the amount field
    const n = e.shiftKey ? it.amount : e.altKey ? Math.max(1, Math.floor(it.amount / 2)) : undefined;
    const d = { key, slot: it.slot, x: e.clientX, y: e.clientY, item: it, n }; dragRef.current = d; setDrag(d); setSel({ key, slot: it.slot }); setMenu(null);
  };
  const onMove = (e: RPointerEvent) => { if (!dragRef.current) return; const d = { ...dragRef.current, x: e.clientX, y: e.clientY }; dragRef.current = d; setDrag(d); };
  const onUp = (e?: RPointerEvent) => {
    const d = dragRef.current; dragRef.current = null; setDrag(null);
    // the slot under the cursor at release: the enter/leave tracking first, else the element under the point
    // (the game's page does not always deliver pointerenter while a button is held)
    let target = over;
    if (d && !target && e) {
      const el = document.elementFromPoint(e.clientX, e.clientY)?.closest('.inv-slot') as HTMLElement | null;
      const grid = el?.closest('[data-key]') as HTMLElement | null;
      if (el && grid) target = { key: grid.dataset.key as Key, slot: Number(el.dataset.slot) };
    }
    if (d && target && !(target.key === d.key && target.slot === d.slot)) post('move', { from: d.key, to: target.key, fromSlot: d.slot, toSlot: target.slot, amount: d.n ?? (amount > 0 && amount < d.item.amount ? amount : d.item.amount) });
    setOver(null);
  };
  const onWheel = (it: Item) => (e: React.WheelEvent) => { if (!selected || selected.slot !== it.slot) return; setAmount((a) => Math.max(1, Math.min(it.amount, a + (e.deltaY < 0 ? 1 : -1)))); };

  /* ── actions ── */
  const act = (name: string, it: Item, key: Key) => {
    setMenu(null);
    if (name === 'use') post('use', { slot: it.slot });
    else if (name === 'give') post('give', { slot: it.slot, amount });
    else if (name === 'drop') post('drop', { slot: it.slot });
    else if (name === 'move' && C.other) post('move', { from: key, to: key === 'player' ? 'other' : 'player', fromSlot: it.slot, toSlot: firstFree(key === 'player' ? 'other' : 'player'), amount: it.amount });
    else if (name === 'split' && C.player) post('move', { from: key, to: key, fromSlot: it.slot, toSlot: firstFree(key), amount: Math.max(1, Math.min(it.amount - 1, Math.floor(it.amount / 2))) });
    else if (name === 'buy') post('buy', { slot: it.slot, amount });
  };
  const firstFree = (key: Key) => { const c = C[key]; if (!c) return 1; const used = new Set(c.items.map((i) => i.slot)); for (let s = 1; s <= c.slots; s++) if (!used.has(s)) return s; return 1; };

  if (!open || !C.player) return <Boxes boxes={boxes} img={img} t={t} />;
  const other = C.other;
  const filter = (c: Container, key: Key) => {
    const needle = q.trim().toLowerCase();
    return c.items.filter((i) => (key !== 'player' || cat === 'all' || catOf(i) === cat) && (!needle || i.label.toLowerCase().includes(needle) || (i.description || '').toLowerCase().includes(needle)));
  };
  const grid = (c: Container, key: Key, from: number) => {
    const shown = filter(c, key); const bySlot: Record<number, Item> = {}; shown.forEach((i) => { bySlot[i.slot] = i; });
    const filtering = q.trim() !== '' || (key === 'player' && cat !== 'all');
    let order = Array.from({ length: c.slots - from + 1 }, (_, i) => from + i);
    if (sort !== 'slot') { const items = shown.filter((i) => i.slot >= from).sort((a, b) => sort === 'name' ? a.label.localeCompare(b.label) : sort === 'amount' ? b.amount - a.amount : b.weight * b.amount - a.weight * a.amount); order = [...items.map((i) => i.slot), ...order.filter((s) => !bySlot[s])]; }
    return order.map((slot) => {
      const it = bySlot[slot]; const hidden = filtering && !it && c.items.some((i) => i.slot === slot);
      return slotEl(key, slot, it, hidden, c);
    });
  };
  // a plain render function, NOT a component declared inside App: a component type created per render
  // remounts every slot on each state change, and the element under the pointer dies mid-click / mid-drag
  const slotEl = (keyName: Key, slot: number, it: Item | undefined, hidden: boolean, c: Container) => {
    const isSel = sel && sel.key === keyName && sel.slot === slot; const isOver = over && over.key === keyName && over.slot === slot;
    const cls = 'inv-slot' + (it ? ' is-' + (it.rarity || 'common') : ' inv-slot--empty') + (isSel ? ' is-on' : '') + (isOver ? ' is-over' : '') + (drag && drag.key === keyName && drag.slot === slot ? ' is-dragging' : '') + (hidden ? ' is-dim' : '') + (c.kind === 'shop' && it ? ' inv-slot--price' : '');
    return (
      <div key={slot} className={cls} data-slot={slot}
        onPointerEnter={() => dragRef.current && setOver({ key: keyName, slot })} onPointerLeave={() => setOver((o) => (o && o.key === keyName && o.slot === slot ? null : o))}
        onPointerDown={it ? startDrag(keyName, it) : undefined} onClick={(e) => { e.stopPropagation(); if (it) setSel({ key: keyName, slot }); }}
        onContextMenu={(e) => { e.preventDefault(); e.stopPropagation(); if (it) { setSel({ key: keyName, slot }); setMenu({ key: keyName, slot, x: e.clientX, y: e.clientY }); } }}
        onDoubleClick={() => it && (c.kind === 'shop' ? act('buy', it, keyName) : keyName === 'player' && it.useable ? act('use', it, keyName) : other && act('move', it, keyName))}
        onWheel={it ? onWheel(it) : undefined} title={it ? t('ui.tip_drag') : ''}>
        {keyName === 'player' && slot <= hotbar && <span className="inv-slot__key lxr-mono">{slot}</span>}
        {it && <>
          <span className="inv-slot__count lxr-mono">{it.amount}</span>
          <img className="inv-slot__img" src={img(it)} alt="" draggable={false} onError={(e) => { const el = e.target as HTMLImageElement; el.style.display = 'none'; el.nextElementSibling?.classList.remove('lxr-hidden'); }} />
          <div className="inv-slot__tile lxr-hidden">{(it.label || '?').charAt(0).toUpperCase()}</div>
          <span className="inv-slot__w lxr-mono">{kg(it.weight * it.amount)}</span>
          <span className="inv-slot__foot"><span className="inv-slot__name">{it.label}</span></span>
          {it.fresh != null && <span className="inv-slot__fresh"><i style={{ width: Math.round(it.fresh * 100) + '%' }} /></span>}
          {it.info?.quality != null && it.type === 'weapon' && <span className="inv-slot__fresh inv-slot__fresh--q"><i style={{ width: Math.max(0, Math.min(100, Number(it.info.quality))) + '%' }} /></span>}
          {c.kind === 'shop' && it.price != null && <span className="slot-price lxr-mono">{money(it.price)}</span>}
          {it.legal === false && <span className="inv-slot__flag lxr-mono">{t('ui.illegal')}</span>}
        </>}
      </div>
    );
  };

  const weightBar = (c: Container) => { if (!isFinite(c.maxWeight) || c.kind === 'shop') return null; const pct = c.maxWeight > 0 ? Math.min(100, (c.weight / c.maxWeight) * 100) : 0; return <><div className="inv-weight"><span className="eyebrow">{c.label}</span><span className="lxr-grow" /><span className="inv-weight__text lxr-mono">{kg(c.weight)} / {kg(c.maxWeight)} · {c.items.length}/{c.slots} {t('ui.slots')}</span></div><div className="inv-weight__bar"><div className={'inv-weight__fill' + (pct > 90 ? ' is-heavy' : '')} style={{ width: pct + '%' }} /></div></>; };
  const menuItem = menu && C[menu.key]?.items.find((i) => i.slot === menu.slot);

  return (
    <div id="app" onPointerMove={onMove} onPointerUp={onUp} onPointerCancel={onUp}>
      <div className="inv-dim" />
      <header className="inv-top">
        <div className="inv-brand"><img className="inv-logo" src="img/lxrcore-logo.png" alt="" /><div><h1 className="inv-title">{t('ui.inventory')}</h1><div className="eyebrow">{C.player.label}</div></div></div>
        <div className="inv-tools lxr-hit">
          <input className="lxr-input inv-search" placeholder={t('ui.search')} value={q} onChange={(e) => setQ(e.target.value)} />
          <div className="inv-seg">{(['slot', 'name', 'amount', 'weight'] as Sort[]).map((s) => <button key={s} className="lxr-chip" aria-pressed={sort === s} onClick={() => setSort(s)}>{s === 'slot' ? '#' : t('ui.sort_' + s)}</button>)}</div>
          <button className="btn" onClick={() => post('sort')}>{t('ui.sort')}</button>
          <span className="inv-esc eyebrow"><span className="lxr-key">ESC</span> {t('ui.close')}</span>
        </div>
      </header>

      {/* the satchel */}
      <section className="inv-col inv-col--player lxr-hit">
        {weightBar(C.player)}
        <div className="inv-cats">
          <button className="lxr-chip" aria-pressed={cat === 'all'} onClick={() => setCat('all')}>{t('ui.all')}</button>
          {cats.map((c) => <button key={c} className="lxr-chip" aria-pressed={cat === c} onClick={() => setCat(c)}>{t('ui.cat_' + c)}</button>)}
        </div>
        <div className="inv-hotbar" data-key="player">{grid({ ...C.player, slots: hotbar }, 'player', 1)}</div>
        <div className="inv-grid" data-key="player">{grid(C.player, 'player', hotbar + 1)}</div>
      </section>

      {/* the middle: what is picked, what you wear */}
      <section className="inv-mid">
        {selected && (
          <aside className="inv-detail lxr-hit">
            <div className="inv-detail__head"><div className="inv-detail__tile"><img src={img(selected)} alt="" onError={(e) => { (e.target as HTMLImageElement).style.visibility = 'hidden'; }} /></div><div><div className="inv-detail__name">{selected.label}</div><div className="inv-detail__meta lxr-mono">× {selected.amount} · {kg(selected.weight * selected.amount)} · {t('ui.rarity_' + (selected.rarity || 'common'))}{selected.legal === false ? ' · ' + t('ui.illegal') : ''}</div></div></div>
            {selected.description && <p className="inv-detail__desc">{selected.description}</p>}
            <div className="inv-detail__info lxr-mono">
              {selected.fresh != null && <span>{selected.fresh > 0.3 ? t('ui.fresh') : t('ui.spoiling')} {Math.round(selected.fresh * 100)}%</span>}
              {selected.info?.quality != null && <span>{t('ui.condition')} {Math.round(Number(selected.info.quality))}%</span>}
              {selected.info?.serie && <span>{t('ui.serial')} {selected.info.serie}</span>}
              {Object.entries(selected.info || {}).filter(([k]) => !['quality', 'serie', 'made'].includes(k)).map(([k, v]) => <span key={k}>{k} {typeof v === 'object' ? JSON.stringify(v) : String(v)}</span>)}
            </div>
            <div className="inv-actions">
              <label className="inv-amount"><span className="eyebrow">{t('ui.amount')}</span><input className="lxr-input" type="number" min={1} max={selected.amount} value={amount} onChange={(e) => setAmount(Math.max(1, Math.min(selected.amount, Number(e.target.value) || 1)))} /></label>
              {sel?.key === 'player' && selected.useable && <button className="btn btn--primary" onClick={() => act('use', selected, 'player')}>{t('ui.use')}</button>}
              {sel?.key === 'player' && <button className="btn" onClick={() => act('give', selected, 'player')}>{t('ui.give_closest')}</button>}
              {sel?.key === 'player' && <button className="btn" onClick={() => act('drop', selected, 'player')}>{t('ui.drop')}</button>}
              {sel?.key === 'player' && selected.amount > 1 && <button className="btn" onClick={() => act('split', selected, 'player')}>{t('ui.split')}</button>}
              {other && other.kind !== 'shop' && <button className="btn" onClick={() => act('move', selected, sel!.key)}>{sel?.key === 'player' ? t('ui.put') : t('ui.take')}</button>}
              {other && other.kind === 'shop' && sel?.key === 'other' && <button className="btn btn--primary" onClick={() => act('buy', selected, 'other')}>{t('ui.buy')} {money((selected.price || 0) * amount)}</button>}
            </div>
          </aside>
        )}
        {!other && wearing && (
          <section className="inv-wear lxr-hit">
            <div className="eyebrow">{t('ui.wearing')}</div>
            {(() => {
              // every piece the character wears (lxr-clothing's Wearing), the known dozen with their icons first
              const icons = Object.fromEntries(WEAR); const known = WEAR.map(([c]) => c);
              const cats = [...known.filter((c) => wearing[c]?.worn), ...Object.keys(wearing).filter((c) => wearing[c]?.worn && !known.includes(c)).sort()];
              const label = (c: string) => (L['ui.wear_' + c] ? t('ui.wear_' + c) : (wearLabels[c] || c));
              const anyOn = cats.some((c) => !wearing[c].hidden), anyOff = cats.some((c) => wearing[c].hidden);
              return <>
                <div className="inv-wear__grid">{cats.map((c) => { const w = wearing[c]; return <button key={c} className={'inv-wear__slot' + (w.hidden ? ' is-off' : '')} title={w.hidden ? t('ui.put_on') : t('ui.take_off')} onClick={() => post('wear', { cat: c, hidden: !w.hidden })}><svg className="inv-wear__ico" viewBox="0 0 24 24"><path d={icons[c] || 'M6 4h12v16H6z'} /></svg><span className="inv-wear__name">{label(c)}</span></button>; })}
                  {!cats.length && <span className="inv-wear__none lxr-mono">{t('ui.nothing_worn')}</span>}</div>
                <div className="inv-wear__all">{anyOn && <button className="btn" onClick={() => post('wear', { all: true })}>{t('ui.undress')}</button>}{anyOff && <button className="btn" onClick={() => post('wear', { all: false })}>{t('ui.dress')}</button>}</div>
              </>;
            })()}
          </section>
        )}
      </section>

      {/* the other side */}
      {other && (
        <section className="inv-col inv-col--other lxr-hit">
          {weightBar(other) || <div className="inv-weight"><span className="eyebrow">{other.label}</span></div>}
          {other.kind === 'trade' && other.trade && (
            <div className="inv-trade">
              <div className="inv-trade__head"><span className="eyebrow">{t('ui.trade_with', { name: other.trade.partner })}</span><span className="lxr-grow" />
                <span className={'lxr-mono inv-trade__state' + (other.trade.confirmed.theirs ? ' is-ok' : '')}>{other.trade.confirmed.theirs ? t('ui.partner_confirmed', { name: other.trade.partner }) : t('ui.waiting_partner', { name: other.trade.partner })}</span></div>
              <div className="inv-trade__cash">
                <label className="inv-amount"><span className="eyebrow">{t('ui.offer_cash')}</span><input className="lxr-input" type="number" min={0} defaultValue={other.trade.money.mine} onBlur={(e) => post('trade', { money: Math.max(0, Number(e.target.value) || 0) })} onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }} /></label>
                <span className="lxr-mono inv-trade__theirmoney">{t('ui.their_offer')}: {money(other.trade.money.theirs)}</span>
              </div>
              <div className="inv-trade__actions">
                <button className={'btn' + (other.trade.confirmed.mine ? '' : ' btn--primary')} onClick={() => post('trade', { confirm: true })}>{other.trade.confirmed.mine ? t('ui.unconfirm') : t('ui.confirm')}</button>
                <button className="btn" onClick={() => post('trade', { cancel: true })}>{t('ui.cancel_trade')}</button>
              </div>
            </div>
          )}
          {other.kind !== 'shop' && other.kind !== 'trade' && (
            <div className="inv-transfer">
              {other.kind !== 'otherplayer' && <><button className="btn" onClick={() => post('transfer', { direction: 'put', mode: 'all' })}>{t('ui.put_all')}</button><button className="btn" onClick={() => post('transfer', { direction: 'put', mode: 'matching' })}>{t('ui.put_matching')}</button></>}
              <button className="btn" onClick={() => post('transfer', { direction: 'take', mode: 'all' })}>{t('ui.take_all')}</button><button className="btn" onClick={() => post('transfer', { direction: 'take', mode: 'matching' })}>{t('ui.take_matching')}</button>
            </div>
          )}
          <div className="inv-grid" data-key="other">{grid(other, 'other', 1)}</div>
          {other.kind === 'trade' && other.trade && (
            <>
              <div className="inv-weight"><span className="eyebrow">{t('ui.their_offer')}</span><span className="lxr-grow" /><span className="lxr-mono inv-weight__text">{other.trade.theirs.length}/{other.trade.theirSlots}</span></div>
              <div className="inv-grid inv-grid--theirs">{Array.from({ length: other.trade.theirSlots }, (_, i) => i + 1).map((slot) => { const it = other.trade!.theirs.find((x) => x.slot === slot); return (
                <div key={slot} className={'inv-slot inv-slot--ro' + (it ? ' is-' + (it.rarity || 'common') : ' inv-slot--empty')} onClick={() => it && setSel(null)}>
                  {it && <><span className="inv-slot__count lxr-mono">{it.amount}</span><img className="inv-slot__img" src={img(it)} alt="" draggable={false} /><span className="inv-slot__foot"><span className="inv-slot__name">{it.label}</span></span></>}
                </div>); })}</div>
            </>
          )}
        </section>
      )}

      {/* right-click */}
      {menu && menuItem && (
        <div className="inv-menu lxr-hit" style={{ left: menu.x, top: menu.y }} onClick={(e) => e.stopPropagation()}>
          <div className="inv-menu__head lxr-mono">{menuItem.label}</div>
          {menu.key === 'player' && menuItem.useable && <button onClick={() => act('use', menuItem, 'player')}>{t('ui.use')}</button>}
          {menu.key === 'player' && <button onClick={() => act('give', menuItem, 'player')}>{t('ui.give_closest')}</button>}
          {menu.key === 'player' && <button onClick={() => act('drop', menuItem, 'player')}>{t('ui.drop')}</button>}
          {menu.key === 'player' && menuItem.amount > 1 && <button onClick={() => act('split', menuItem, 'player')}>{t('ui.split')}</button>}
          {other && other.kind !== 'shop' && <button onClick={() => act('move', menuItem, menu.key)}>{menu.key === 'player' ? t('ui.put') : t('ui.take')}</button>}
          {other && other.kind === 'shop' && menu.key === 'other' && <button onClick={() => act('buy', menuItem, 'other')}>{t('ui.buy')}</button>}
        </div>
      )}

      {/* the ghost under the cursor */}
      {drag && <div className="inv-ghost" style={{ left: drag.x, top: drag.y }}><img src={img(drag.item)} alt="" /><span className="lxr-mono">{drag.n ?? (amount > 0 && amount < drag.item.amount ? amount : drag.item.amount)}</span></div>}
      <Boxes boxes={boxes} img={img} t={t} />
    </div>
  );
}

function Boxes({ boxes, img, t }: { boxes: Box[]; img: (b: Box) => string; t: (k: string) => string }) {
  if (!boxes.length) return null;
  return <div id="itembox">{boxes.map((b) => <div key={b.id} className={'inv-box inv-box--' + b.kind}><img src={img(b)} alt="" onError={(e) => { (e.target as HTMLImageElement).style.visibility = 'hidden'; }} /><div><div className="inv-box__label">{b.label}</div><div className="lxr-mono inv-box__kind">{b.kind === 'add' ? t('ui.received') : t('ui.removed')} × {b.amount}</div></div></div>)}</div>;
}

void pad;
