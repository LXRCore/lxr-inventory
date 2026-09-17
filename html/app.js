/* ═══════════════════════════════════════════════════════════════════════════
   🐺 LXR-INVENTORY — NUI logic (vanilla, HTML5 drag & drop)
   Messages in : { action: 'open'|'update'|'close'|'itembox' }
   Messages out: close, move { from, to, fromSlot, toSlot, amount }, use { slot },
                 give { slot, amount }, drop {}
   The UI never mutates its own state; every change comes back from the server.
   © 2026 iBoss21 / LXRCore | lxrcore.com | All Rights Reserved
   ═══════════════════════════════════════════════════════════════════════════ */
(() => {
    'use strict';

    const resource = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'lxr-inventory';
    const $ = (id) => document.getElementById(id);
    const HOTKEYS = ['1', '2', '3', '4', '5'];

    let locale = {};
    let hotbar = 5;
    let containers = { player: null, other: null };
    let selected = null;   // { container, slot }
    let dragging = null;   // { container, slot }

    const postNUI = (event, payload) =>
        fetch(`https://${resource}/${event}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload || {}),
        }).then((r) => r.json()).catch(() => ({}));

    const t = (key, fallback) => (locale[key] !== undefined ? locale[key] : (fallback !== undefined ? fallback : key));
    const kg = (grams) => (Number(grams || 0) / 1000).toFixed(1) + ' kg';
    const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

    // ── rendering ─────────────────────────────────────────────────────────
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

    function renderGrid(key) {
        const c = containers[key];
        const grid = $(key === 'player' ? 'grid-player' : 'grid-other');
        grid.innerHTML = '';
        if (!c) return;
        const bySlot = {};
        (c.items || []).forEach((it) => { bySlot[it.slot] = it; });
        for (let slot = 1; slot <= c.slots; slot++) {
            const item = bySlot[slot];
            const el = document.createElement('div');
            el.className = 'inv-slot';
            el.dataset.slot = slot;
            el.dataset.container = key;
            if (key === 'player' && slot <= hotbar) {
                el.classList.add('inv-slot--hotbar');
                el.dataset.key = HOTKEYS[slot - 1] || String(slot);
            }
            if (item) {
                el.classList.add('inv-slot--filled');
                el.draggable = true;
                el.appendChild(itemVisual(item));
                const amount = document.createElement('span');
                amount.className = 'inv-slot__amount';
                amount.textContent = item.amount;
                el.appendChild(amount);
                if (c.kind === 'shop') {
                    const price = document.createElement('span');
                    price.className = 'inv-slot__price';
                    price.textContent = '$' + (item.price || 0);
                    el.appendChild(price);
                }
                if (item.info && typeof item.info.quality === 'number') {
                    const q = document.createElement('div');
                    q.className = 'inv-slot__quality';
                    const fill = document.createElement('i');
                    fill.style.width = Math.max(0, Math.min(100, item.info.quality)) + '%';
                    q.appendChild(fill);
                    el.appendChild(q);
                }
                const label = document.createElement('span');
                label.className = 'inv-slot__label';
                label.textContent = item.label || item.name;
                el.appendChild(label);
                if (selected && selected.container === key && selected.slot === slot) el.classList.add('inv-slot--selected');
                el.addEventListener('mouseenter', (e) => showTooltip(item, c, e));
                el.addEventListener('mousemove', moveTooltip);
                el.addEventListener('mouseleave', hideTooltip);
                el.addEventListener('click', () => { selected = { container: key, slot }; updateButtons(); renderGrid(key); });
                el.addEventListener('dblclick', () => {
                    if (key === 'player' && item.useable) postNUI('use', { slot });
                    else if (key === 'other') quickMove('other', slot, item.amount);
                    else if (key === 'player' && containers.other) quickMove('player', slot, item.amount);
                });
                el.addEventListener('dragstart', (e) => {
                    dragging = { container: key, slot };
                    el.classList.add('inv-slot--dragging');
                    e.dataTransfer.effectAllowed = 'move';
                    e.dataTransfer.setData('text/plain', `${key}:${slot}`);
                });
                el.addEventListener('dragend', () => { dragging = null; el.classList.remove('inv-slot--dragging'); });
            }
            el.addEventListener('dragover', (e) => { if (dragging) { e.preventDefault(); el.classList.add('inv-slot--over'); } });
            el.addEventListener('dragleave', () => el.classList.remove('inv-slot--over'));
            el.addEventListener('drop', (e) => {
                e.preventDefault();
                el.classList.remove('inv-slot--over');
                if (!dragging) return;
                postNUI('move', { from: dragging.container, to: key, fromSlot: dragging.slot, toSlot: slot, amount: amountValue() });
                dragging = null;
            });
            grid.appendChild(el);
        }
    }

    function renderWeight(key) {
        const c = containers[key];
        const fill = $(key === 'player' ? 'player-weight-fill' : 'other-weight-fill');
        const text = $(key === 'player' ? 'player-weight-text' : 'other-weight-text');
        if (!c || !isFinite(c.maxWeight)) { if (fill) fill.style.width = '0'; if (text) text.textContent = ''; return; }
        const pct = c.maxWeight > 0 ? Math.min(100, (c.weight / c.maxWeight) * 100) : 0;
        fill.style.width = pct + '%';
        fill.classList.toggle('is-heavy', pct > 90);
        text.textContent = `${kg(c.weight)} / ${kg(c.maxWeight)}`;
    }

    function render() {
        $('player-label').textContent = (containers.player && containers.player.label) || t('ui.your_satchel', 'Your satchel');
        renderGrid('player');
        renderWeight('player');
        const other = containers.other;
        $('panel-other').classList.toggle('hidden', !other);
        if (other) {
            $('other-label').textContent = other.label || other.id;
            $('other-weight').classList.toggle('hidden', other.kind === 'shop');
            renderGrid('other');
            renderWeight('other');
        }
        updateButtons();
    }

    function amountValue() {
        const n = parseInt($('amount').value, 10);
        return Number.isFinite(n) && n > 0 ? n : undefined;
    }

    function quickMove(fromKey, slot, amount) {
        const toKey = fromKey === 'player' ? 'other' : 'player';
        const target = containers[toKey];
        if (!target) return;
        const used = new Set((target.items || []).map((i) => i.slot));
        let free = null;
        for (let s = 1; s <= target.slots; s++) { if (!used.has(s)) { free = s; break; } }
        if (!free) return;
        postNUI('move', { from: fromKey, to: toKey, fromSlot: slot, toSlot: free, amount: amountValue() || amount });
    }

    function updateButtons() {
        const item = selectedItem();
        const mine = selected && selected.container === 'player';
        $('btn-use').disabled = !(mine && item && item.useable);
        $('btn-give').disabled = !(mine && item);
        $('btn-drop').disabled = !(mine && item);
    }

    function selectedItem() {
        if (!selected) return null;
        const c = containers[selected.container];
        return c && (c.items || []).find((i) => i.slot === selected.slot) || null;
    }

    // ── tooltip ───────────────────────────────────────────────────────────
    function showTooltip(item, c, e) {
        const tip = $('tooltip');
        const meta = [];
        if (item.weight) meta.push(`${t('ui.weight', 'Weight')}: ${kg(item.weight * item.amount)}`);
        if (c.kind === 'shop') meta.push(`${t('ui.price', 'Price')}: $${item.price || 0}`);
        if (item.info) {
            if (item.info.serie) meta.push(`#${item.info.serie}`);
            if (typeof item.info.quality === 'number') meta.push(`${Math.round(item.info.quality)}%`);
        }
        tip.innerHTML = `<b>${esc(item.label || item.name)}</b>${esc(item.description || '')}<div class="meta">${esc(meta.join(' · '))}</div>`;
        tip.classList.remove('hidden');
        moveTooltip(e);
    }
    function moveTooltip(e) {
        const tip = $('tooltip');
        const x = Math.min(e.clientX + 16, window.innerWidth - tip.offsetWidth - 12);
        const y = Math.min(e.clientY + 16, window.innerHeight - tip.offsetHeight - 12);
        tip.style.left = x + 'px';
        tip.style.top = y + 'px';
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
    $('btn-close').addEventListener('click', () => postNUI('close'));
    $('btn-use').addEventListener('click', () => { if (selected && selected.container === 'player') postNUI('use', { slot: selected.slot }); });
    $('btn-give').addEventListener('click', () => { if (selected && selected.container === 'player') postNUI('give', { slot: selected.slot, amount: amountValue() }); });
    $('btn-drop').addEventListener('click', () => { if (selected && selected.container === 'player') postNUI('drop', {}); });
    document.addEventListener('keyup', (e) => {
        if (e.key === 'Escape' || e.key === 'Tab') postNUI('close');
    });
    document.addEventListener('keydown', (e) => { if (e.key === 'Tab') e.preventDefault(); });

    window.addEventListener('message', (event) => {
        const data = event.data || {};
        switch (data.action) {
            case 'open':
                locale = data.locale || locale;
                hotbar = Number(data.hotbar) || 5;
                ['t-amount', 'btn-use', 'btn-give', 'btn-drop', 'btn-close'].forEach((id) => {
                    const key = { 't-amount': 'ui.amount', 'btn-use': 'ui.use', 'btn-give': 'ui.give', 'btn-drop': 'ui.drop', 'btn-close': 'ui.close' }[id];
                    $(id).textContent = t(key, $(id).textContent);
                });
                containers = { player: data.player || null, other: data.other || null };
                selected = null;
                $('amount').value = 1;
                render();
                $('app').classList.remove('hidden');
                break;
            case 'update':
                if (data.player) containers.player = data.player;
                if (data.other === false) containers.other = null;
                else if (data.other) containers.other = data.other;
                render();
                break;
            case 'close':
                $('app').classList.add('hidden');
                hideTooltip();
                selected = null;
                dragging = null;
                break;
            case 'itembox':
                itemBox(data.item || {}, data.kind, data.amount);
                break;
            default:
                break;
        }
    });
})();
