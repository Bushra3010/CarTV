/* Backseat web player. Everything is stored in this browser: playlists in IndexedDB, the rest in localStorage. */
(() => {
  'use strict';

  const $ = (sel, el = document) => el.querySelector(sel);
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2));

  const SAMPLE = `#EXTM3U
#EXTINF:-1 group-title="Test streams (HLS)",Apple Bipbop (fMP4, multi-audio)
https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8
#EXTINF:-1 group-title="Test streams (HLS)",Apple Bipbop 16x9
https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8
#EXTINF:-1 group-title="Test streams (HLS)",Apple Bipbop (audio only)
https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear0/prog_index.m3u8
#EXTINF:-1 group-title="Test streams (HLS)",Big Buck Bunny (Mux)
https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8
#EXTINF:-1 group-title="Test streams (HLS)",Tears of Steel (Unified Streaming)
https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8
#EXTINF:-1 group-title="Sample movies (MP4)",Sintel (trailer)
https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4
#EXTINF:-1 group-title="Sample movies (MP4)",Big Buck Bunny (10s clip)
https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4
#EXTINF:-1 group-title="Sample movies (MP4)",Jellyfish (10s clip)
https://test-videos.co.uk/vids/jellyfish/mp4/h264/720/Jellyfish_720_10s_1MB.mp4
#EXTINF:-1 group-title="Sample movies (MP4)",Flower (MDN, CC0)
https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4`;

  // ---------- Storage ----------
  const LS = {
    get(k, d) { try { const v = JSON.parse(localStorage.getItem('backseat.' + k)); return v ?? d; } catch { return d; } },
    set(k, v) { try { localStorage.setItem('backseat.' + k, JSON.stringify(v)); } catch { /* quota: ignore */ } },
  };

  const dbp = new Promise((resolve, reject) => {
    const req = indexedDB.open('backseat', 1);
    req.onupgradeneeded = () => req.result.createObjectStore('channels');
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  async function idb(mode, fn) {
    const db = await dbp;
    return new Promise((resolve, reject) => {
      const tx = db.transaction('channels', mode);
      const req = fn(tx.objectStore('channels'));
      tx.oncomplete = () => resolve(req && req.result);
      tx.onerror = () => reject(tx.error);
    });
  }
  const putChannels = (id, list) => idb('readwrite', (s) => s.put(list, id));
  const getChannels = (id) => idb('readonly', (s) => s.get(id));
  const deleteChannels = (id) => idb('readwrite', (s) => s.delete(id));

  // ---------- M3U ----------
  const ATTR = /([A-Za-z0-9_-]+)="([^"]*)"/g;
  const isHLSManifest = (t) => /#EXT-X-(TARGETDURATION|STREAM-INF|MEDIA-SEQUENCE)/.test(t);

  function parseExtInf(line) {
    let inQuotes = false, comma = -1;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (c === '"') inQuotes = !inQuotes;
      else if (c === ',' && !inQuotes) { comma = i; break; }
    }
    const head = comma >= 0 ? line.slice(0, comma) : line;
    const name = comma >= 0 ? line.slice(comma + 1).trim() : '';
    const attrs = {};
    for (const m of head.matchAll(ATTR)) attrs[m[1].toLowerCase()] = m[2];
    return { attrs, name };
  }

  function parseM3U(text, sourceId) {
    const out = [], seen = new Set();
    let name = null, logo = null, group = null;
    for (const raw of text.split(/\r?\n/)) {
      const line = raw.trim();
      if (!line) continue;
      if (line.startsWith('#EXTINF')) {
        const info = parseExtInf(line);
        name = info.name || info.attrs['tvg-name'] || null;
        logo = info.attrs['tvg-logo'] || null;
        group = info.attrs['group-title'] || null;
      } else if (line.startsWith('#EXTGRP:')) {
        group = line.slice(8).trim();
      } else if (line.startsWith('#')) {
        continue;
      } else {
        const url = line;
        const key = sourceId + '|' + url;
        if (!seen.has(key)) {
          seen.add(key);
          let fallback = url;
          try { fallback = decodeURIComponent(new URL(url).pathname.split('/').pop()) || url; } catch { /* keep url */ }
          out.push({ key, sourceId, name: name || fallback, url, logo, group: group || 'Ungrouped' });
        }
        name = logo = group = null;
      }
    }
    return out;
  }

  // ---------- State ----------
  const state = {
    sources: LS.get('sources', []),
    favorites: LS.get('favorites', []),
    recents: LS.get('recents', []),
    positions: LS.get('positions', {}),
    channels: new Map(),
    groups: new Map(),
    view: { type: 'home' },
    group: null,
    favOnly: false,
    query: '',
    limit: 300,
    visible: [],
    current: null,
    queue: [],
    carMode: false,
  };
  const lookup = new Map();

  const saveSources = () => LS.set('sources', state.sources);
  const saveFavs = () => LS.set('favorites', state.favorites);
  const saveRecents = () => LS.set('recents', state.recents);
  const savePositions = () => LS.set('positions', state.positions);

  function setChannels(id, list) {
    state.channels.set(id, list);
    const seen = new Set();
    state.groups.set(id, list.map((c) => c.group).filter((g) => !seen.has(g) && seen.add(g)));
  }

  const isFav = (ch) => state.favorites.some((f) => f.key === ch.key);
  function toggleFav(ch) {
    if (isFav(ch)) state.favorites = state.favorites.filter((f) => f.key !== ch.key);
    else state.favorites.push(ch);
    saveFavs();
  }

  // ---------- Sources ----------
  async function fetchText(url) {
    let res;
    try {
      res = await fetch(url, { cache: 'no-store' });
    } catch {
      if (location.protocol === 'https:' && url.startsWith('http:')) {
        throw new Error('This link uses http://, which browsers block on secure pages. Download the file and use "Upload file", or use the iPhone app.');
      }
      throw new Error("Couldn't read this link. Many IPTV servers don't let browsers read playlists (CORS). Download the .m3u file and use \"Upload file\", or use the iPhone app.");
    }
    if (!res.ok) throw new Error(`The server answered with HTTP ${res.status}.`);
    return res.text();
  }

  function channelsFromText(text, source) {
    if (isHLSManifest(text) && source.url) {
      return [{ key: source.id + '|' + source.url, sourceId: source.id, name: source.name, url: source.url, logo: null, group: 'Streams' }];
    }
    const list = parseM3U(text, source.id);
    if (!list.length) throw new Error('No channels found. Is this an M3U playlist?');
    return list;
  }

  async function addSource({ name, url, text, kind }) {
    const source = { id: uid(), kind, name: name || 'Playlist', url: url || null, addedAt: Date.now(), updatedAt: Date.now(), error: null };
    if (kind === 'url') {
      if (!/^https?:\/\//i.test(url)) throw new Error('Enter a full link that starts with http:// or https://');
      if (!name) { try { source.name = new URL(url).hostname; } catch { /* keep */ } }
      text = await fetchText(url);
    }
    const list = channelsFromText(text, source);
    source.count = list.length;
    await putChannels(source.id, list);
    setChannels(source.id, list);
    state.sources.push(source);
    saveSources();
    return source;
  }

  async function refreshSource(id) {
    const s = state.sources.find((x) => x.id === id);
    if (!s) return;
    try {
      const text = s.kind === 'sample' ? SAMPLE : await fetchText(s.url);
      const list = channelsFromText(text, s);
      await putChannels(id, list);
      setChannels(id, list);
      Object.assign(s, { count: list.length, updatedAt: Date.now(), error: null });
      toast('Playlist refreshed');
    } catch (e) {
      s.error = e.message;
      toast(e.message);
    }
    saveSources();
    render();
  }

  async function removeSource(id) {
    state.sources = state.sources.filter((s) => s.id !== id);
    state.channels.delete(id);
    state.groups.delete(id);
    state.favorites = state.favorites.filter((c) => c.sourceId !== id);
    state.recents = state.recents.filter((c) => c.sourceId !== id);
    saveSources(); saveFavs(); saveRecents();
    await deleteChannels(id);
    if (state.view.type === 'source' && state.view.id === id) state.view = { type: 'home' };
    render();
  }

  // ---------- Rendering ----------
  function logoHTML(ch, cls = 'logo') {
    const initials = esc(ch.name.replace(/[^\p{L}\p{N}\s]/gu, '').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || '▶');
    if (!ch.logo) return `<span class="${cls}">${initials}</span>`;
    return `<span class="${cls}"><img src="${esc(ch.logo)}" alt="" loading="lazy" referrerpolicy="no-referrer" onerror="this.parentNode.textContent='${initials}'"></span>`;
  }

  function progressHTML(ch) {
    const p = state.positions[ch.key];
    if (!p || !p.d) return '';
    return `<div class="bar"><i style="width:${Math.min(100, (p.t / p.d) * 100).toFixed(1)}%"></i></div>`;
  }

  function rowHTML(ch, showGroup = true) {
    lookup.set(ch.key, ch);
    const playing = state.current && state.current.key === ch.key;
    return `<li class="ch${playing ? ' playing' : ''}">
      <button class="ch-main" data-action="play" data-key="${esc(ch.key)}">
        ${logoHTML(ch)}
        <span class="ch-text"><div class="ch-name">${playing ? '▶ ' : ''}${esc(ch.name)}</div>${showGroup ? `<div class="ch-group">${esc(ch.group)}</div>` : ''}${progressHTML(ch)}</span>
      </button>
      <button class="star${isFav(ch) ? ' on' : ''}" data-action="fav" data-key="${esc(ch.key)}" aria-label="${isFav(ch) ? 'Remove from favourites' : 'Add to favourites'}">${isFav(ch) ? '★' : '☆'}</button>
    </li>`;
  }

  function listHTML(list, showGroup = true) {
    state.visible = list;
    const shown = list.slice(0, state.limit);
    let html = `<ul class="list">${shown.map((c) => rowHTML(c, showGroup)).join('')}</ul>`;
    if (list.length > shown.length) html += `<button class="btn more" data-action="more">Show more (${(list.length - shown.length).toLocaleString()} left)</button>`;
    return html;
  }

  function railHTML(title, list, action) {
    if (!list.length) return '';
    list.forEach((c) => lookup.set(c.key, c));
    return `<div class="rail-title"><h2>${esc(title)}</h2>${action || ''}</div>
      <div class="rail">${list.map((c) => `<button class="tile" data-action="play-rail" data-rail="${esc(title)}" data-key="${esc(c.key)}">${logoHTML(c)}${progressHTML(c)}<div class="ch-name">${esc(c.name)}</div></button>`).join('')}</div>`;
  }

  function renderNav() {
    const v = state.view;
    const item = (label, view, extra = '', active = false) =>
      `<button class="nav-item${active ? ' active' : ''}" data-action="nav" data-view="${view}">${label}${extra}</button>`;
    let html = item('🏠&nbsp; Home', 'home', '', v.type === 'home' && !state.query);
    html += item('★&nbsp; Favourites', 'favorites', `<span class="count">${state.favorites.length || ''}</span>`, v.type === 'favorites' && !state.query);
    html += `<div class="nav-title">Playlists</div>`;
    for (const s of state.sources) {
      html += `<button class="nav-item${v.type === 'source' && v.id === s.id && !state.query ? ' active' : ''}" data-action="nav" data-view="source" data-id="${s.id}">☰&nbsp; ${esc(s.name)}${s.error ? '<span class="err" title="' + esc(s.error) + '">!</span>' : `<span class="count">${(s.count || 0).toLocaleString()}</span>`}</button>`;
    }
    html += `<button class="nav-item" data-action="open-add" style="color:var(--accent)">＋&nbsp; Add playlist</button>`;
    html += `<div class="nav-title">More</div>`;
    html += item('🚘&nbsp; Cast to Car', 'cast', '', v.type === 'cast' && !state.query);
    html += item('⚙︎&nbsp; Settings', 'settings', '', v.type === 'settings' && !state.query);
    $('#nav').innerHTML = html;
    const tab = v.type === 'source' ? 'playlists' : v.type === 'favorites' ? 'home' : v.type;
    document.querySelectorAll('#tabbar button').forEach((b) => b.classList.toggle('active', b.dataset.view === tab && !state.query));
  }

  function renderView() {
    lookup.clear();
    const el = $('#view');
    const q = state.query.trim().toLowerCase();

    if (q) {
      const results = [];
      for (const s of state.sources) for (const c of state.channels.get(s.id) || []) if (c.name.toLowerCase().includes(q)) results.push(c);
      el.innerHTML = `<h1>Search</h1><p class="sub">${results.length.toLocaleString()} result${results.length === 1 ? '' : 's'} for “${esc(state.query)}”</p>` +
        (results.length ? listHTML(results) : `<div class="empty"><div class="big-icon">⌕</div><h2>No matches</h2><p>Try a shorter name.</p></div>`);
      return;
    }

    const v = state.view;
    if (v.type === 'playlists') {
      el.innerHTML = `<div class="view-head"><div class="grow"><h1>Playlists</h1><p class="sub" style="margin:0">Your playlists are stored only in this browser.</p></div>
        <div class="tools"><button class="btn small primary" data-action="open-add">+ Add</button></div></div>` +
        (state.sources.length
          ? `<ul class="list">${state.sources.map((s) => `<li class="ch"><button class="ch-main" data-action="nav" data-view="source" data-id="${s.id}">
              <span class="logo">☰</span><span class="ch-text"><div class="ch-name">${esc(s.name)}</div>
              <div class="ch-group">${s.kind === 'file' ? 'Uploaded file' : s.kind === 'sample' ? 'Sample' : 'M3U link'} · ${(s.count || 0).toLocaleString()} entries</div>
              ${s.error ? `<div class="ch-group" style="color:var(--danger)">${esc(s.error)}</div>` : ''}</span></button><span class="star">›</span></li>`).join('')}</ul>`
          : `<div class="empty"><div class="big-icon">☰</div><h2>No playlists yet</h2><p>Backseat comes with no channels. Add a playlist you have the right to use.</p>
             <div class="btns"><button class="btn primary" data-action="open-add">Add a playlist</button><button class="btn" data-action="add-sample">Try sample streams</button></div></div>`);
      return;
    }
    if (v.type === 'cast') {
      const airplay = 'webkitShowPlaybackTargetPicker' in HTMLVideoElement.prototype;
      const remote = 'remote' in HTMLMediaElement.prototype;
      const how = airplay ? 'AirPlay (Safari)' : remote ? 'Cast (Chrome / Edge)' : null;
      el.innerHTML = `<h1>Cast to Car</h1><p class="sub">Send what you're watching to a car display, wireless adapter or TV.</p>
        <div class="card-box">
          <div class="cast-status">${how ? `✅ This browser can cast with <strong>${how}</strong>.` : '⚠️ This browser has no built-in casting. Use Safari (AirPlay) or Chrome (Cast), or the iPhone app.'}</div>
          ${state.current ? `<div class="cast-now"><div><div class="ch-group">Now playing</div><div class="ch-name">${esc(state.current.name)}</div></div>
            <div class="btns">${how ? '<button class="btn primary" data-action="cast">Cast now</button>' : ''}<button class="btn" data-action="car">🚗 Car mode</button></div></div>`
            : '<p class="sub" style="margin:12px 0 0">Play a channel first, then come back here or tap 📺 in the player.</p>'}
        </div>
        <div class="card-box"><h2>Cast what you're watching</h2><ol class="steps-list">
          <li>Connect to the same Wi-Fi as the car's wireless adapter or the TV.</li>
          <li>Play a channel, then tap 📺 in the player (or <em>Cast now</em> above) and choose the screen.</li>
          <li>On Chrome you can also use the browser menu › Cast… › Cast tab.</li></ol></div>
        <div class="card-box"><h2>Mirror your whole screen</h2><ol class="steps-list">
          <li>iPhone: open Control Center › Screen Mirroring and pick the display.</li>
          <li>Android: open Quick Settings › Cast or Smart View.</li></ol></div>
        <p class="notice">For passengers only. Never watch video while driving.</p>`;
      return;
    }
    if (v.type === 'settings') {
      el.innerHTML = `<h1>Settings</h1><p class="sub">Everything is stored only in this browser. There's no account.</p>
        <div class="card-box"><h2>Playback</h2>
          <label class="switch"><input type="checkbox" data-action="setting-car" ${LS.get('openInCar', false) ? 'checked' : ''}><span>Open videos in car mode</span></label></div>
        <div class="card-box"><h2>Data</h2><div class="btns" style="justify-content:flex-start">
          <button class="btn" data-action="clear-recents">Clear recently played</button>
          <button class="btn" data-action="clear-progress">Clear watch progress</button>
          <button class="btn danger" data-action="clear-all">Delete all playlists and data</button></div></div>
        <div class="card-box"><h2>Help</h2>
          <details><summary>Why won't a playlist load?</summary><p class="sub">Many IPTV servers don't let browsers read playlists (CORS). Download the .m3u file and use <em>Upload file</em>, or use the iPhone app.</p></details>
          <details><summary>Why won't a channel play?</summary><p class="sub">Secure websites can't play http:// streams, and some formats can't be decoded by browsers. The iPhone app plays these.</p></details></div>
        <div class="card-box"><h2>About</h2><p class="sub">Backseat is a media player. It provides no channels or content. Only add playlists you have the right to use.</p>
          <div class="btns" style="justify-content:flex-start"><a class="btn" href="/about/">About Backseat</a><a class="btn" href="/privacy/">Privacy</a><a class="btn" href="/support/">Support</a></div></div>`;
      return;
    }
    if (v.type === 'favorites') {
      el.innerHTML = `<h1>Favourites</h1><p class="sub">Tap ☆ on any channel to add it here.</p>` +
        (state.favorites.length ? listHTML(state.favorites) : `<div class="empty"><div class="big-icon">☆</div><h2>No favourites yet</h2></div>`);
      return;
    }

    if (v.type === 'source') {
      const s = state.sources.find((x) => x.id === v.id);
      if (!s) { state.view = { type: 'home' }; return renderView(); }
      let list = state.channels.get(s.id) || [];
      if (state.favOnly) list = list.filter(isFav);
      if (state.group) list = list.filter((c) => c.group === state.group);
      const groups = state.groups.get(s.id) || [];
      const chips = [`<button class="chip${!state.group && !state.favOnly ? ' active' : ''}" data-action="group" data-group="">All</button>`,
        `<button class="chip${state.favOnly ? ' active' : ''}" data-action="fav-only">★ Favourites</button>`,
        ...groups.map((g) => `<button class="chip${state.group === g ? ' active' : ''}" data-action="group" data-group="${esc(g)}">${esc(g)}</button>`)].join('');
      el.innerHTML = `<div class="view-head"><div class="grow"><h1>${esc(s.name)}</h1>
          <p class="sub" style="margin:0">${(s.count || 0).toLocaleString()} entries · updated ${new Date(s.updatedAt).toLocaleString()}</p>
          ${s.error ? `<p class="error">${esc(s.error)}</p>` : ''}</div>
          <div class="tools">${s.kind !== 'file' ? `<button class="btn small" data-action="refresh" data-id="${s.id}">Refresh</button>` : ''}
          <button class="btn small" data-action="rename" data-id="${s.id}">Rename</button>
          <button class="btn small danger" data-action="delete" data-id="${s.id}">Delete</button></div></div>
        <div class="chips">${chips}</div>` +
        (list.length ? listHTML(list, !state.group) : `<div class="empty"><h2>Nothing here</h2><p>${state.favOnly ? 'No favourites in this playlist yet.' : 'This group is empty.'}</p></div>`);
      return;
    }

    // Home
    if (!state.sources.length && !state.recents.length) {
      el.innerHTML = `<div class="empty"><div class="big-icon">📺</div><h2>Bring your own playlist</h2>
        <p>Add an M3U link or file, then watch here or cast to a TV. Everything stays in this browser.</p>
        <div class="btns"><button class="btn primary" data-action="open-add">Add a playlist</button><button class="btn" data-action="add-sample">Try sample streams</button></div>
        <p style="margin-top:28px;font-size:13px">Backseat provides no channels. Add only playlists you have the right to use.</p></div>`;
      return;
    }
    const cont = state.recents.filter((c) => state.positions[c.key]);
    el.innerHTML = `<h1>Home</h1><p class="sub">Pick up where you left off, or open one of your playlists.</p>` +
      railHTML('Continue watching', cont) +
      railHTML('Recently played', state.recents) +
      railHTML('Favourites', state.favorites, `<a href="#" data-action="nav" data-view="favorites">See all</a>`) +
      (state.recents.length ? '' : `<div class="empty" style="padding:40px 0"><p>Open one of your playlists and pick a channel to start watching.</p></div>`);
  }

  function render() {
    renderNav();
    renderView();
    renderPlayerInfo();
  }

  // ---------- Player ----------
  const video = $('#video');
  const viz = $('#viz');
  let hls = null;
  let lastSave = 0;
  let resumeTarget = null;

  const isLive = () => !Number.isFinite(video.duration) || video.duration === 0;
  const queueIndex = () => (state.current ? state.queue.findIndex((c) => c.key === state.current.key) : -1);

  function showStatus(msg, retry = true) {
    const st = $('#status');
    const next = queueIndex() < state.queue.length - 1;
    st.innerHTML = `<div><p>⚠️ ${esc(msg)}</p>${retry ? '<button class="btn primary" data-action="retry">Retry</button> ' : ''}${next ? '<button class="btn" data-action="next">Next channel</button>' : ''}</div>`;
    st.hidden = false;
  }
  const hideStatus = () => { $('#status').hidden = true; };

  function play(ch, queue) {
    if (!ch) return;
    savePosition(true);
    if (queue) state.queue = queue;
    else if (!state.queue.some((c) => c.key === ch.key)) state.queue = [ch];
    state.current = ch;
    hideStatus();
    $('#player').hidden = false;

    if (hls) { hls.destroy(); hls = null; }
    video.removeAttribute('src');
    video.load();

    const url = ch.url;
    if (location.protocol === 'https:' && /^http:/i.test(url)) {
      showStatus('This stream uses http://, which browsers block on secure pages. It will play in the iPhone app.', false);
    } else {
      const pos = state.positions[ch.key];
      resumeTarget = pos ? pos.t : null;
      load(url);
    }

    state.recents = [ch, ...state.recents.filter((c) => c.key !== ch.key)].slice(0, 30);
    saveRecents();
    updateMediaSession();
    render();
    if (LS.get('openInCar', false) && !state.carMode) enterCar();
    else if (!state.carMode) window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  const DIRECT_FILE = /\.(mp4|m4v|mov|webm|mp3|m4a|aac|ogg|wav)(\?|$)/i;
  const canNativeHLS = () => !!video.canPlayType('application/vnd.apple.mpegurl');
  let tried = new Set();

  // Picks a playback engine and falls back to the other one before giving up:
  // Safari uses its own HLS player (best there, keeps AirPlay); other browsers start with
  // hls.js and fall back to their built-in HLS support, which copes with some older streams.
  function load(url) {
    tried = new Set();
    const hlsOK = window.Hls && window.Hls.isSupported();
    if (DIRECT_FILE.test(url) || !hlsOK) return loadNative(url);
    if (/Apple/.test(navigator.vendor) && canNativeHLS()) return loadNative(url);
    return loadHls(url);
  }

  function loadNative(url) {
    tried.add('native');
    if (hls) { hls.destroy(); hls = null; }
    video.src = url;
    video.play().catch(() => { /* autoplay may need a tap */ });
  }

  function loadHls(url) {
    tried.add('hls');
    video.removeAttribute('src');
    hls = new window.Hls({ enableWorker: true });
    hls.on(window.Hls.Events.ERROR, (_e, data) => {
      if (!data.fatal) return;
      if (!tried.has('native') && canNativeHLS()) return loadNative(url);
      if (hls) { hls.destroy(); hls = null; }
      if (data.type === 'networkError') showStatus("The stream couldn't be reached. It may be offline, or the server blocks browsers (CORS). Try the iPhone app.");
      else showStatus('This stream uses a format the browser cannot play. Try the iPhone app.');
    });
    hls.loadSource(url);
    hls.attachMedia(video);
    video.play().catch(() => {});
  }

  function step(delta) {
    const i = queueIndex();
    const next = state.queue[i + delta];
    if (next) play(next);
  }

  function stop() {
    savePosition(true);
    if (hls) { hls.destroy(); hls = null; }
    video.pause();
    video.removeAttribute('src');
    video.load();
    state.current = null;
    exitCar();
    $('#player').hidden = true;
    render();
  }

  function savePosition(force) {
    const ch = state.current;
    if (!ch || isLive()) return;
    const now = Date.now();
    if (!force && now - lastSave < 5000) return;
    lastSave = now;
    const t = video.currentTime, d = video.duration;
    if (d < 30) return;
    if (t < 5 || t > d - 15) delete state.positions[ch.key];
    else state.positions[ch.key] = { t, d, at: now };
    savePositions();
  }

  function renderPlayerInfo() {
    const ch = state.current;
    if (!ch) return;
    $('#now-title').textContent = ch.name;
    $('#now-group').textContent = ch.group;
    $('#live').hidden = !isLive() || video.readyState < 1;
    const i = queueIndex();
    document.querySelectorAll('[data-action="prev"]').forEach((b) => (b.disabled = i <= 0));
    document.querySelectorAll('[data-action="next"]').forEach((b) => (b.disabled = i < 0 || i >= state.queue.length - 1));
    const fav = $('#fav-current');
    fav.textContent = isFav(ch) ? '★' : '☆';
    fav.classList.toggle('on', isFav(ch));
    const icon = video.paused ? '▶' : '⏸';
    $('#toggle').textContent = icon;
    $('#car-toggle').textContent = icon;
    $('#cast').hidden = !(video.webkitShowPlaybackTargetPicker || (video.remote && !hls));
    if (state.carMode) renderCar();
  }

  function updateMediaSession() {
    if (!('mediaSession' in navigator) || !state.current) return;
    navigator.mediaSession.metadata = new MediaMetadata({ title: state.current.name, artist: state.current.group, album: 'Backseat' });
    navigator.mediaSession.setActionHandler('nexttrack', () => step(1));
    navigator.mediaSession.setActionHandler('previoustrack', () => step(-1));
  }

  async function cast() {
    try {
      if (video.webkitShowPlaybackTargetPicker) video.webkitShowPlaybackTargetPicker();
      else if (video.remote) await video.remote.prompt();
    } catch (e) {
      toast(e && e.name === 'NotSupportedError' ? 'This stream can’t be cast from the browser. Use the iPhone app or your browser’s Cast menu.' : 'No cast device was chosen.');
    }
  }

  video.addEventListener('loadedmetadata', () => {
    if (resumeTarget && Number.isFinite(video.duration) && resumeTarget < video.duration - 15) video.currentTime = resumeTarget;
    resumeTarget = null;
    renderPlayerInfo();
    updateViz();
  });
  video.addEventListener('timeupdate', () => { savePosition(false); if (state.carMode) $('#car-time').textContent = timeText(); });
  video.addEventListener('play', () => { renderPlayerInfo(); updateViz(); });
  video.addEventListener('pause', () => { renderPlayerInfo(); savePosition(true); });
  video.addEventListener('playing', hideStatus);
  video.addEventListener('ended', () => { if (state.current) { delete state.positions[state.current.key]; savePositions(); } step(1); });
  video.addEventListener('error', () => {
    if (hls || !state.current || !video.getAttribute('src')) return;
    const url = state.current.url;
    if (!DIRECT_FILE.test(url) && !tried.has('hls') && window.Hls && window.Hls.isSupported()) return loadHls(url);
    showStatus('This stream could not be played. It may be offline, or use a format the browser cannot decode.');
  });

  // ---------- Audio visualizer (follows play/pause; browsers can't read cross-origin audio) ----------
  let vizFrame = 0;
  function updateViz() {
    const audioOnly = state.current && video.readyState >= 1 && video.videoWidth === 0;
    viz.hidden = !audioOnly;
    cancelAnimationFrame(vizFrame);
    if (audioOnly) drawViz();
  }
  function drawViz() {
    const ctx = viz.getContext('2d');
    const w = (viz.width = viz.clientWidth * devicePixelRatio);
    const h = (viz.height = viz.clientHeight * devicePixelRatio);
    const t = performance.now() / 1000;
    const grad = ctx.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, '#111633'); grad.addColorStop(1, '#000');
    ctx.fillStyle = grad; ctx.fillRect(0, 0, w, h);
    const n = 32, gap = w * 0.006, bw = (w - gap * (n + 1)) / n;
    for (let i = 0; i < n; i++) {
      const f1 = 1.3 + ((i * 7919) % 13) / 6, f2 = 0.7 + ((i * 104729) % 11) / 9;
      let v = 0.5 + 0.3 * Math.sin(t * f1 + i) + 0.2 * Math.sin(t * f2 * 2.1 + i * 0.7);
      v = video.paused ? 0.06 : Math.max(0.06, Math.min(1, v));
      const bh = h * 0.6 * v, x = gap + i * (bw + gap), y = h - h * 0.08 - bh;
      const g = ctx.createLinearGradient(0, y, 0, y + bh);
      g.addColorStop(0, '#ffb03c'); g.addColorStop(1, 'rgba(255,176,60,.3)');
      ctx.fillStyle = g;
      ctx.beginPath(); ctx.roundRect ? ctx.roundRect(x, y, bw, bh, bw / 2) : ctx.rect(x, y, bw, bh); ctx.fill();
    }
    ctx.fillStyle = '#fff'; ctx.font = `600 ${Math.round(16 * devicePixelRatio)}px -apple-system, sans-serif`; ctx.textAlign = 'center';
    ctx.fillText('♪ ' + (state.current ? state.current.name : ''), w / 2, h * 0.16);
    if (!video.paused) vizFrame = requestAnimationFrame(drawViz);
  }

  // ---------- Car mode ----------
  function timeText() {
    if (isLive()) return 'Live';
    const f = (s) => { s = Math.max(0, Math.floor(s)); const hh = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, ss = String(s % 60).padStart(2, '0'); return hh ? `${hh}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`; };
    return `${f(video.currentTime)} / ${f(video.duration)}`;
  }
  function renderCar() {
    const ch = state.current;
    if (!ch) return;
    $('#car-title').textContent = ch.name;
    $('#car-group').textContent = ch.group;
    $('#car-time').textContent = timeText();
    const i = Math.max(0, queueIndex());
    const nearby = state.queue.slice(Math.max(0, i - 20), i + 21);
    nearby.forEach((c) => lookup.set(c.key, c));
    $('#car-strip').innerHTML = nearby.map((c) => `<button class="car-tile${c.key === ch.key ? ' current' : ''}" data-action="play-queue" data-key="${esc(c.key)}">${logoHTML(c)}<span>${esc(c.name)}</span></button>`).join('');
    const cur = $('#car-strip .current');
    if (cur) cur.scrollIntoView({ inline: 'center', block: 'nearest' });
  }
  function enterCar() {
    if (!state.current) return;
    state.carMode = true;
    $('#car').hidden = false;
    $('#car-stage').append(video, viz, $('#status'));
    renderCar();
    const el = document.documentElement;
    if (el.requestFullscreen) el.requestFullscreen().catch(() => {});
    if (screen.orientation && screen.orientation.lock) screen.orientation.lock('landscape').catch(() => {});
    updateViz();
  }
  function exitCar() {
    if (!state.carMode) return;
    state.carMode = false;
    $('#car').hidden = true;
    $('#stage').append(video, viz, $('#status'));
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
    updateViz();
  }
  document.addEventListener('fullscreenchange', () => { if (!document.fullscreenElement && state.carMode) exitCar(); });

  // ---------- Add dialog ----------
  const dialog = $('#add');
  let tab = 'url';
  function openAdd() {
    $('#add-form').reset();
    $('#add-error').hidden = true;
    setTab('url');
    dialog.showModal();
  }
  function setTab(t) {
    tab = t;
    dialog.querySelectorAll('.tab').forEach((b) => b.classList.toggle('active', b.dataset.tab === t));
    dialog.querySelectorAll('.pane').forEach((p) => (p.hidden = p.dataset.pane !== t));
    $('#add-submit').textContent = t === 'sample' ? 'Add sample streams' : 'Add';
  }
  async function addSample() {
    const existing = state.sources.find((s) => s.kind === 'sample');
    if (existing) { state.view = { type: 'source', id: existing.id }; render(); return; }
    const s = await addSource({ name: 'Sample test streams', text: SAMPLE, kind: 'sample' });
    state.view = { type: 'source', id: s.id };
    render();
  }
  $('#add-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target, err = $('#add-error'), btn = $('#add-submit');
    err.hidden = true;
    btn.disabled = true;
    try {
      if (tab === 'sample') {
        await addSample();
      } else if (tab === 'file') {
        const file = form.file.files[0];
        if (!file) throw new Error('Choose a .m3u file first.');
        const text = await file.text();
        const s = await addSource({ name: form.fname.value.trim() || file.name.replace(/\.m3u8?$/i, ''), text, kind: 'file' });
        state.view = { type: 'source', id: s.id };
      } else {
        const url = form.url.value.trim();
        if (!url) throw new Error('Paste a playlist link.');
        const s = await addSource({ name: form.name.value.trim(), url, kind: 'url' });
        state.view = { type: 'source', id: s.id };
      }
      dialog.close();
      state.query = ''; $('#search').value = '';
      state.group = null; state.favOnly = false; state.limit = 300;
      render();
    } catch (ex) {
      err.textContent = ex.message;
      err.hidden = false;
    } finally {
      btn.disabled = false;
    }
  });
  dialog.querySelectorAll('.tab').forEach((b) => b.addEventListener('click', () => setTab(b.dataset.tab)));

  // ---------- Toast ----------
  let toastTimer;
  function toast(msg) {
    const t = $('#toast');
    t.textContent = msg;
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => (t.hidden = true), 3500);
  }

  // ---------- Events ----------
  document.addEventListener('click', async (e) => {
    const el = e.target.closest('[data-action]');
    if (!el) return;
    const a = el.dataset.action;
    const key = el.dataset.key;
    switch (a) {
      case 'nav':
        e.preventDefault();
        state.view = { type: el.dataset.view, id: el.dataset.id };
        state.group = null; state.favOnly = false; state.limit = 300;
        state.query = ''; $('#search').value = '';
        render();
        break;
      case 'open-add': openAdd(); break;
      case 'close-add': dialog.close(); break;
      case 'add-sample': await addSample(); break;
      case 'play': play(lookup.get(key), state.visible); break;
      case 'play-rail': {
        const title = el.dataset.rail;
        const list = title === 'Favourites' ? state.favorites : title === 'Continue watching' ? state.recents.filter((c) => state.positions[c.key]) : state.recents;
        play(lookup.get(key), list.slice());
        break;
      }
      case 'play-queue': play(lookup.get(key)); break;
      case 'fav': { const ch = lookup.get(key); if (ch) { toggleFav(ch); render(); } break; }
      case 'fav-current': if (state.current) { toggleFav(state.current); render(); } break;
      case 'group': state.group = el.dataset.group || null; if (!state.group) state.favOnly = false; state.limit = 300; renderView(); break;
      case 'fav-only': state.favOnly = !state.favOnly; state.limit = 300; renderView(); break;
      case 'more': state.limit += 500; renderView(); break;
      case 'refresh': el.disabled = true; await refreshSource(el.dataset.id); break;
      case 'rename': {
        const s = state.sources.find((x) => x.id === el.dataset.id);
        const name = s && prompt('Rename playlist', s.name);
        if (name && name.trim()) { s.name = name.trim(); saveSources(); render(); }
        break;
      }
      case 'delete': {
        const s = state.sources.find((x) => x.id === el.dataset.id);
        if (s && confirm(`Delete “${s.name}”? Its favourites and history are removed too.`)) await removeSource(s.id);
        break;
      }
      case 'toggle': video.paused ? video.play().catch(() => {}) : video.pause(); break;
      case 'prev': step(-1); break;
      case 'next': step(1); break;
      case 'retry': if (state.current) play(state.current); break;
      case 'stop': stop(); break;
      case 'cast': cast(); break;
      case 'car': enterCar(); break;
      case 'car-exit': exitCar(); break;
      case 'setting-car': LS.set('openInCar', el.checked); toast(el.checked ? 'Videos will open in car mode' : 'Car mode is off by default'); break;
      case 'clear-recents': state.recents = []; saveRecents(); toast('Recently played cleared'); render(); break;
      case 'clear-progress': state.positions = {}; savePositions(); toast('Watch progress cleared'); render(); break;
      case 'clear-all':
        if (confirm('Delete every playlist, favourite and watch history from this browser?')) {
          stop();
          for (const s of state.sources.slice()) await removeSource(s.id);
          state.favorites = []; state.recents = []; state.positions = {};
          saveFavs(); saveRecents(); savePositions();
          state.view = { type: 'home' };
          toast('All data deleted');
          render();
        }
        break;
      case 'back30': if (!isLive()) video.currentTime = Math.max(0, video.currentTime - 30); break;
      case 'fwd30': if (!isLive()) video.currentTime = Math.min(video.duration - 1, video.currentTime + 30); break;
    }
  });

  let searchTimer;
  $('#search').addEventListener('input', (e) => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => { state.query = e.target.value; state.limit = 300; render(); }, 150);
  });

  document.addEventListener('keydown', (e) => {
    if (e.target.closest('input, textarea, dialog') || e.metaKey || e.ctrlKey || e.altKey) return;
    if (!state.current) return;
    if (e.key === ' ') { e.preventDefault(); video.paused ? video.play().catch(() => {}) : video.pause(); }
    else if (e.key === 'n' || e.key === 'N') step(1);
    else if (e.key === 'p' || e.key === 'P') step(-1);
    else if (e.key === 'c' || e.key === 'C') state.carMode ? exitCar() : enterCar();
    else if (e.key === 'Escape' && state.carMode) exitCar();
  });

  window.addEventListener('pagehide', () => savePosition(true));

  // ---------- Start ----------
  (async () => {
    try {
      for (const s of state.sources) {
        const list = await getChannels(s.id);
        if (list) setChannels(s.id, list);
      }
    } catch {
      toast('Saved playlists could not be loaded in this browser.');
    }
    render();
  })();
})();
