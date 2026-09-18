/* ═══════════════════════════════════════════════════════════════════════════
   LXR-INVENTORY — NUI logic (vanilla, no build step)
   Receives { action: 'open' | 'update' | 'itembox' | 'close' } from the client
   and posts { move, use, drop, give, wear, close }. The server validates
   everything; this file only renders and relays slots.
   © 2026 iBoss21 / LXRCore | lxrcore.com | All Rights Reserved
   ═══════════════════════════════════════════════════════════════════════════ */
(() => {
    'use strict';
    const resource = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'lxr-inventory';
    const $ = (id) => document.getElementById(id);
    let locale = {}, containers = { player: null, other: null }, selected = null, dragging = null, hotbar = 5, wearing = null;

    const postNUI = (event, payload) => fetch(`https://${resource}/${event}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(payload || {}) }).then((r) => r.json()).catch(() => ({}));
    const t = (key, fallback) => (locale[key] !== undefined ? locale[key] : (fallback !== undefined ? fallback : key.split('.').pop().replace(/_/g, ' ')));
    const kg = (grams) => (Number(grams || 0) / 1000).toFixed(1) + ' kg';
    const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const money = (n) => '$' + Number(n || 0).toFixed(2);

    // ── item visual: image, or a letter tile when there is none ───────────
    function itemVisual(item) {
        const img = document.createElement('img');
        img.className = 'inv-slot__img';
        img.src = `images/${item.image || (item.name + '.png')}`;
        img.alt = '';
        img.addEventListener('error', () => {
            const tile = document.createElement('div');
            tile.className = 'inv-slot__tile';
            tile.textContent = (item.label || item.name || '?').trim().charAt(0).toUpperCase();
            img.replaceWith(tile);
        }, { once: true });
        return img;
    }

    // ── slots ─────────────────────────────────────────────────────────────
    function slotEl(key, c, slot, item, isHot) {
        const el = document.createElement('div');
        el.className = 'inv-slot' + (item ? '' : ' inv-slot--empty') + (c.kind === 'shop' && item ? ' inv-slot--price' : '');
        el.dataset.slot = slot;
        if (selected && selected.container === key && selected.slot === slot) el.classList.add('is-on');
        if (isHot) el.insertAdjacentHTML('beforeend', `<span class="inv-slot__key">${slot}</span>`);
        if (item) {
            el.draggable = true;
            el.appendChild(itemVisual(item));
            el.insertAdjacentHTML('beforeend', `<span class="inv-slot__count">${Number(item.amount) || 1}</span><span class="inv-slot__name">${esc(item.label || item.name)}</span>${c.kind === 'shop' ? '<span class="slot-price">' + esc(money(item.price)) + '</span>' : ''}`);
            el.addEventListener('click', () => { selected = { container: key, slot }; render(); });
            el.addEventListener('dblclick', () => quickMove(key, slot));
            el.addEventListener('mouseenter', (e) => showTooltip(item, c, e));
            el.addEventListener('mousemove', moveTooltip);
            el.addEventListener('mouseleave', hideTooltip);
            el.addEventListener('dragstart', (e) => { dragging = { container: key, slot }; el.classList.add('is-dragging'); e.dataTransfer.effectAllowed = 'move'; hideTooltip(); });
            el.addEventListener('dragend', () => { dragging = null; el.classList.remove('is-dragging'); });
        }
        el.addEventListener('dragover', (e) => { if (dragging) { e.preventDefault(); el.classList.add('is-over'); } });
        el.addEventListener('dragleave', () => el.classList.remove('is-over'));
        el.addEventListener('drop', (e) => {
            e.preventDefault(); el.classList.remove('is-over');
            if (!dragging) return;
            if (dragging.container === key && dragging.slot === slot) return;
            postNUI('move', { from: dragging.container, to: key, fromSlot: dragging.slot, toSlot: slot, amount: amountValue() });
            dragging = null;
        });
        return el;
    }
    function renderGrid(key) {
        const c = containers[key];
        const grid = $(key === 'player' ? 'grid-player' : 'grid-other');
        const hot = key === 'player' ? $('hotbar-player') : null;
        grid.innerHTML = ''; if (hot) hot.innerHTML = '';
        if (!c) return;
        const bySlot = {};
        (c.items || []).forEach((it) => { bySlot[it.slot] = it; });
        for (let slot = 1; slot <= c.slots; slot++) {
            const isHot = key === 'player' && slot <= hotbar;
            (isHot ? hot : grid).appendChild(slotEl(key, c, slot, bySlot[slot], isHot));
        }
    }
    function renderWeight(key) {
        const c = containers[key];
        const fill = $(key === 'player' ? 'player-fill' : 'other-fill'), text = $(key === 'player' ? 'player-weight' : 'other-weight');
        if (!c || !isFinite(c.maxWeight) || c.kind === 'shop') { fill.style.width = '0'; text.textContent = c && c.kind === 'shop' ? t('ui.shop', 'Shop') : ''; return; }
        const pct = c.maxWeight > 0 ? Math.min(100, (c.weight / c.maxWeight) * 100) : 0;
        fill.style.width = pct + '%'; fill.classList.toggle('is-heavy', pct > 90);
        text.textContent = `${kg(c.weight)} / ${kg(c.maxWeight)}`;
    }

    // ── what you wear ─────────────────────────────────────────────────────
    const WEAR = [['hats', 'M4 14l2-8h12l2 8M2 14h20v3H2z'], ['masks', 'M4 8h16v6l-4 5H8l-4-5z'], ['eyewear', 'M2 12h4a3 3 0 0 0 6 0h0a3 3 0 0 0 6 0h4M8 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm8 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'],
        ['coats', 'M8 3l4 3 4-3 4 3v15H4V6zM12 6v15'], ['shirts_full', 'M7 3l5 2 5-2 3 4-3 2v12H7V9L4 7z'], ['vests', 'M8 3l4 4 4-4 3 3v14H5V6z'],
        ['pants', 'M6 3h12l1 18h-5l-2-9-2 9H5z'], ['boots', 'M7 3h6v9l6 4v5H7z'], ['gloves', 'M8 21V9l-2-3 2-3 2 3 2-3 2 3 2-3 2 3v12z'],
        ['neckwear', 'M12 3l4 5-4 13-4-13z'], ['gunbelts', 'M3 10h18v4H3zM10 10v4M14 10v4'], ['satchels', 'M4 8h16v12H4zM8 8V5h8v3']];
    function renderWear() {
        const grid = $('wear-grid'); grid.innerHTML = '';
        for (const [cat, path] of WEAR) {
            const worn = wearing && wearing[cat] && wearing[cat].worn;
            const hidden = wearing && wearing[cat] && wearing[cat].hidden;
            const el = document.createElement('button');
            el.className = 'inv-wear__slot' + (!worn || hidden ? ' is-off' : '');
            el.innerHTML = `<svg class="inv-wear__ico" viewBox="0 0 24 24"><path d="${path}"/></svg><span class="inv-wear__name">${esc(t('ui.wear_' + cat, cat))}</span>`;
            el.title = worn ? (hidden ? t('ui.put_on', 'Put on') : t('ui.take_off', 'Take off')) : t('ui.nothing_worn', 'Nothing worn');
            if (worn) el.addEventListener('click', () => postNUI('wear', { cat, hidden: !hidden }));
            grid.appendChild(el);
        }
    }

    // ── detail ────────────────────────────────────────────────────────────
    function selectedItem() {
        if (!selected) return null;
        const c = containers[selected.container];
        return c && (c.items || []).find((i) => i.slot === selected.slot) || null;
    }
    function renderDetail() {
        const item = selectedItem();
        $('detail').classList.toggle('hidden', !item);
        if (!item) return;
        const c = containers[selected.container];
        const tile = $('d-tile'); tile.innerHTML = ''; tile.appendChild(itemVisual(item));
        $('d-name').textContent = item.label || item.name;
        const meta = [`× ${item.amount || 1}`, kg((item.weight || 0) * (item.amount || 1))];
        if (c.kind === 'shop') meta.push(money(item.price));
        $('d-meta').textContent = meta.join(' · ');
        $('d-desc').textContent = item.description || '';
        const info = $('d-info'); info.innerHTML = '';
        for (const [k, v] of Object.entries(item.info || {})) if (['string', 'number'].includes(typeof v)) info.insertAdjacentHTML('beforeend', `<span>${esc(k)} <b>${esc(v)}</b></span>`);
        const mine = selected.container === 'player';
        $('btn-use').disabled = !(mine && item.useable);
        $('btn-give').disabled = !mine;
        $('btn-drop').disabled = !mine;
        $('btn-move').disabled = !containers.other;
        $('btn-move').textContent = c.kind === 'shop' && !mine ? t('ui.buy', 'Buy') : (mine ? t('ui.put', 'Put') : t('ui.take', 'Take'));
        $('amount').max = item.amount || 1;
        if (Number($('amount').value) > (item.amount || 1)) $('amount').value = item.amount || 1;
    }
    function amountValue() { const n = parseInt($('amount').value, 10); return Number.isFinite(n) && n > 0 ? n : undefined; }
    function quickMove(fromKey, slot) {
        const toKey = fromKey === 'player' ? 'other' : 'player';
        const target = containers[toKey];
        if (!target) return;
        const used = new Set((target.items || []).map((i) => i.slot));
        let free = null;
        for (let s = 1; s <= target.slots; s++) { if (!used.has(s)) { free = s; break; } }
        if (!free) return;
        postNUI('move', { from: fromKey, to: toKey, fromSlot: slot, toSlot: free, amount: amountValue() });
    }

    function render() {
        $('player-label').textContent = (containers.player && containers.player.label) || t('ui.your_satchel', 'Your satchel');
        renderGrid('player'); renderWeight('player');
        const other = containers.other;
        $('panel-other').classList.toggle('hidden', !other);
        if (other) { $('other-label').textContent = other.label || other.id; renderGrid('other'); renderWeight('other'); }
        $('panel-wear').classList.toggle('hidden', !!other && other.kind !== 'ground');
        renderWear(); renderDetail();
    }

    // ── tooltip ───────────────────────────────────────────────────────────
    function showTooltip(item, c, e) {
        const tip = $('tooltip');
        const meta = [kg((item.weight || 0) * (item.amount || 1))];
        if (c.kind === 'shop') meta.push(money(item.price));
        if (item.info && item.info.serie) meta.push('#' + item.info.serie);
        if (item.info && typeof item.info.quality === 'number') meta.push(Math.round(item.info.quality) + '%');
        tip.innerHTML = `<b>${esc(item.label || item.name)}</b>${esc(item.description || '')}<div class="meta">${esc(meta.join(' · '))}</div>`;
        tip.classList.remove('hidden'); moveTooltip(e);
    }
    function moveTooltip(e) {
        const tip = $('tooltip');
        tip.style.left = Math.min(e.clientX + 16, window.innerWidth - tip.offsetWidth - 12) + 'px';
        tip.style.top = Math.min(e.clientY + 16, window.innerHeight - tip.offsetHeight - 12) + 'px';
    }
    function hideTooltip() { $('tooltip').classList.add('hidden'); }

    // ── item box ──────────────────────────────────────────────────────────
    function itemBox(item, kind, amount) {
        const box = document.createElement('div');
        box.className = 'inv-toast' + (kind === 'remove' ? ' inv-toast--remove' : '');
        box.appendChild(itemVisual(item));
        const text = document.createElement('div');
        text.innerHTML = `${esc(item.label || item.name)} ×${Number(amount) || 1}<small>${esc(kind === 'remove' ? t('ui.removed', 'Removed') : t('ui.received', 'Received'))}</small>`;
        box.appendChild(text);
        $('itembox').appendChild(box);
        setTimeout(() => box.remove(), 3000);
    }

    // ── wiring ────────────────────────────────────────────────────────────
    function applyLocale() {
        const map = { 'l-inventory': 'ui.inventory', 'l-sort': 'ui.sort', 'l-close': 'ui.close', 'l-satchel': 'ui.your_satchel', 'l-wearing': 'ui.wearing', 'l-amount': 'ui.amount', 'btn-use': 'ui.use', 'btn-give': 'ui.give', 'btn-drop': 'ui.drop' };
        for (const [id, key] of Object.entries(map)) $(id).textContent = t(key, $(id).textContent);
    }
    $('btn-use').addEventListener('click', () => { if (selected && selected.container === 'player') postNUI('use', { slot: selected.slot }); });
    $('btn-give').addEventListener('click', () => { if (selected && selected.container === 'player') postNUI('give', { slot: selected.slot, amount: amountValue() }); });
    $('btn-drop').addEventListener('click', () => { if (selected && selected.container === 'player') postNUI('drop', {}); });
    $('btn-move').addEventListener('click', () => {
        if (!selected) return;
        const c = containers[selected.container];
        if (c && c.kind === 'shop' && selected.container !== 'player') {
            postNUI('buy', { slot: selected.slot, amount: amountValue() });
        } else {
            quickMove(selected.container, selected.slot);
        }
    });
    $('btn-sort').addEventListener('click', () => postNUI('sort', {}));
    document.addEventListener('keyup', (e) => { if (e.key === 'Escape' || e.key === 'Tab') postNUI('close'); });
    document.addEventListener('keydown', (e) => { if (e.key === 'Tab') e.preventDefault(); });

    window.addEventListener('message', (event) => {
        const data = event.data || {};
        const th = data.theme || (data.brand && data.brand.theme);
        if (th) document.documentElement.dataset.theme = th;
        switch (data.action) {
            case 'open':
                locale = data.locale || locale; hotbar = Number(data.hotbar) || 5;
                if (data.lang) document.body.classList.toggle('lang-ka', data.lang === 'ka');
                $('srv-name').textContent = (data.brand && data.brand.name) || '';
                containers = { player: data.player || null, other: data.other || null };
                wearing = data.wearing || null;
                selected = null; applyLocale(); $('app').classList.remove('hidden'); render(); break;
            case 'update':
                if (data.player !== undefined) containers.player = data.player;
                if (data.other !== undefined) containers.other = data.other || null;
                if (data.wearing !== undefined) wearing = data.wearing;
                render(); break;
            case 'itembox': itemBox(data.item || {}, data.kind, data.amount); break;
            case 'close': $('app').classList.add('hidden'); hideTooltip(); selected = null; dragging = null; break;
        }
    });
})();
