/* =========================================================
   GLOBAL MUSIC INTELLIGENCE — DASHBOARD
   Vanilla JS + inline SVG charts. No build step, no CDN.
   Data: dashboard/data/dashboard.json (exported from PostgreSQL).
   ========================================================= */

'use strict';

const NS = 'http://www.w3.org/2000/svg';
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const LONG_MONTHS = ['January', 'February', 'March', 'April', 'May', 'June',
                     'July', 'August', 'September', 'October', 'November', 'December'];

const COLORS = { Spotify: '#1ED760', YouTube: '#FF4D4D' };
const NEUTRAL = '#7C9EFF';

const MARKET_NAMES = {
  ar: 'Argentina', at: 'Austria', au: 'Australia', be: 'Belgium', br: 'Brazil',
  ca: 'Canada', ch: 'Switzerland', cl: 'Chile', co: 'Colombia', cz: 'Czechia',
  de: 'Germany', dk: 'Denmark', ee: 'Estonia', es: 'Spain', fi: 'Finland',
  fr: 'France', gb: 'United Kingdom', global: 'Global', ie: 'Ireland',
  is: 'Iceland', it: 'Italy', jp: 'Japan', ke: 'Kenya', kr: 'South Korea',
  lu: 'Luxembourg', mx: 'Mexico', ng: 'Nigeria', nl: 'Netherlands',
  no: 'Norway', nz: 'New Zealand', pe: 'Peru', pl: 'Poland', pt: 'Portugal',
  ro: 'Romania', rs: 'Serbia', ru: 'Russia', se: 'Sweden', tr: 'T\u00fcrkiye',
  tz: 'Tanzania', ua: 'Ukraine', ug: 'Uganda', us: 'United States',
  za: 'South Africa', zw: 'Zimbabwe'
};

const state = { platform: 'All', market: 'global' };
let DATA = null;

/* ---------------- helpers ---------------- */

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const INT = new Intl.NumberFormat('en-US');
const fmtInt = (v) => INT.format(Math.round(v));

function fmtCompact(v) {
  const n = Math.abs(v);
  if (n >= 1e9) return (v / 1e9).toFixed(2) + 'B';
  if (n >= 1e6) return (v / 1e6).toFixed(n >= 1e7 ? 0 : 1) + 'M';
  if (n >= 1e3) return (v / 1e3).toFixed(n >= 1e4 ? 0 : 1) + 'K';
  return String(Math.round(v * 10) / 10);
}

const fmtPct = (v) => (Math.round(v * 10) / 10).toFixed(1) + '%';
const esc = (s) => String(s ?? '').replace(/[&<>"]/g,
  (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const clip = (s, n = 24) => (String(s).length > n ? String(s).slice(0, n - 1) + '\u2026' : String(s));

function svgEl(tag, attrs = {}, parent) {
  const node = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) if (v != null) node.setAttribute(k, v);
  if (parent) parent.appendChild(node);
  return node;
}

function niceMax(max) {
  if (!isFinite(max) || max <= 0) return 1;
  const exp = Math.pow(10, Math.floor(Math.log10(max)));
  const f = max / exp;
  const nf = f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10;
  return nf * exp;
}

function dateLabel(iso) {
  const d = new Date(iso + 'T00:00:00');
  return MONTHS[d.getMonth()] + " '" + String(d.getFullYear()).slice(2);
}

function longDate(iso) {
  const d = new Date(iso + 'T00:00:00');
  return d.getDate() + ' ' + MONTHS[d.getMonth()] + ' ' + d.getFullYear();
}

const activePlatforms = () =>
  state.platform === 'All' ? ['Spotify', 'YouTube'] : [state.platform];

const activeRows = (rows) =>
  rows.filter((r) => !r.platform || activePlatforms().includes(r.platform));

function platformTag(p) {
  return `<span class="tag ${p === 'Spotify' ? 'sp' : 'yt'}">${p === 'Spotify' ? 'SP' : 'YT'}</span>`;
}

/* ---------------- tooltip ---------------- */

const tip = $('#tooltip');

function showTip(ev, html) {
  tip.innerHTML = html;
  tip.classList.add('is-on');
  const x = Math.min(window.innerWidth - 140, Math.max(140, ev.clientX));
  tip.style.left = x + 'px';
  tip.style.top = ev.clientY + 'px';
}

function hideTip() { tip.classList.remove('is-on'); }

function attachTip(node, html) {
  node.addEventListener('mousemove', (ev) => showTip(ev, html));
  node.addEventListener('mouseleave', hideTip);
}

window.addEventListener('scroll', hideTip, { passive: true });

/* ---------------- chart primitives ---------------- */

function chartHost(host, height) {
  host.innerHTML = '';
  const w = Math.max(host.clientWidth || 0, 300);
  const s = svgEl('svg', { viewBox: `0 0 ${w} ${height}`, width: '100%', height, role: 'img' });
  host.appendChild(s);
  return { s, w, h: height };
}

function legend(host, items) {
  host.insertAdjacentHTML('beforeend',
    `<div class="legend">${items.map((i) =>
      `<span><i style="background:${i.color}"></i>${esc(i.label)}</span>`).join('')}</div>`);
}

function lineChart(host, opts) {
  const { series, labels, height = 232, yFmt = fmtCompact, yTicks = 4, area = true } = opts;
  const { s, w, h } = chartHost(host, height);
  const pad = { l: 48, r: 16, t: 14, b: 26 };
  const iw = w - pad.l - pad.r;
  const ih = h - pad.t - pad.b;
  const all = series.flatMap((x) => x.values).filter((v) => v != null && isFinite(v));
  const yMax = niceMax(all.length ? Math.max(...all) : 1);
  const Y = (v) => pad.t + ih - (v / yMax) * ih;
  const n = labels.length;
  const X = (i) => pad.l + (n === 1 ? iw / 2 : (i / (n - 1)) * iw);

  const defs = svgEl('defs', {}, s);

  for (let t = 0; t <= yTicks; t++) {
    const v = (yMax * t) / yTicks;
    const y = Y(v);
    svgEl('line', { x1: pad.l, x2: w - pad.r, y1: y, y2: y, class: 'grid-line' }, s);
    svgEl('text', { x: pad.l - 8, y: y + 3.5, class: 'axis-label', 'text-anchor': 'end' }, s)
      .textContent = yFmt(v);
  }

  const step = Math.max(1, Math.ceil(n / 7));
  labels.forEach((lab, i) => {
    if (i % step !== 0 && i !== n - 1) return;
    svgEl('text', {
      x: X(i), y: h - 7, class: 'axis-label',
      'text-anchor': i === 0 ? 'start' : i === n - 1 ? 'end' : 'middle'
    }, s).textContent = lab;
  });

  series.forEach((ser, si) => {
    const pts = ser.values.map((v, i) => [X(i), Y(v)]);
    const d = pts.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(2)},${p[1].toFixed(2)}`).join(' ');

    if (area && series.length === 1) {
      const gid = 'grad' + si;
      const g = svgEl('linearGradient', { id: gid, x1: 0, y1: 0, x2: 0, y2: 1 }, defs);
      svgEl('stop', { offset: '0%', 'stop-color': ser.color, 'stop-opacity': 0.26 }, g);
      svgEl('stop', { offset: '100%', 'stop-color': ser.color, 'stop-opacity': 0 }, g);
      svgEl('path', {
        d: `${d} L${X(n - 1)},${pad.t + ih} L${X(0)},${pad.t + ih} Z`,
        fill: `url(#${gid})`, stroke: 'none'
      }, s);
    }

    svgEl('path', {
      d, fill: 'none', stroke: ser.color, 'stroke-width': 1.9,
      'stroke-linejoin': 'round', 'stroke-linecap': 'round'
    }, s);
  });

  // hover layer
  const guide = svgEl('line', {
    x1: pad.l, x2: pad.l, y1: pad.t, y2: pad.t + ih,
    stroke: '#3b4350', 'stroke-width': 1, opacity: 0
  }, s);
  const dots = series.map((ser) =>
    svgEl('circle', { r: 3.6, fill: ser.color, stroke: '#0b0d10', 'stroke-width': 1.5, opacity: 0 }, s));

  const hit = svgEl('rect', {
    x: pad.l, y: pad.t, width: iw, height: ih, fill: 'transparent'
  }, s);

  hit.addEventListener('mousemove', (ev) => {
    const rect = s.getBoundingClientRect();
    const rx = (ev.clientX - rect.left) * (w / rect.width);
    let idx = Math.round(((rx - pad.l) / iw) * (n - 1));
    idx = Math.max(0, Math.min(n - 1, idx));
    guide.setAttribute('x1', X(idx));
    guide.setAttribute('x2', X(idx));
    guide.setAttribute('opacity', 0.55);
    series.forEach((ser, i) => {
      dots[i].setAttribute('cx', X(idx));
      dots[i].setAttribute('cy', Y(ser.values[idx]));
      dots[i].setAttribute('opacity', 1);
    });
    showTip(ev, `<b>${esc(labels[idx])}</b>` + series.map((ser) =>
      `<div class="t-sub">${esc(ser.name)}: <b>${yFmt(ser.values[idx])}</b></div>`).join(''));
  });

  hit.addEventListener('mouseleave', () => {
    guide.setAttribute('opacity', 0);
    dots.forEach((d) => d.setAttribute('opacity', 0));
    hideTip();
  });

  if (series.length > 1) legend(host, series.map((x) => ({ label: x.name, color: x.color })));
}

function barChart(host, opts) {
  const {
    categories, series, height = 240, yFmt = fmtCompact,
    yTicks = 4, stacked = false, legendItems = true
  } = opts;
  const { s, w, h } = chartHost(host, height);
  const pad = { l: 46, r: 14, t: 16, b: 26 };
  const iw = w - pad.l - pad.r;
  const ih = h - pad.t - pad.b;

  const totals = categories.map((_, i) =>
    stacked ? series.reduce((a, se) => a + (se.values[i] || 0), 0)
            : Math.max(...series.map((se) => se.values[i] || 0)));
  const yMax = niceMax(Math.max(...totals));
  const Y = (v) => pad.t + ih - (v / yMax) * ih;

  for (let t = 0; t <= yTicks; t++) {
    const v = (yMax * t) / yTicks;
    const y = Y(v);
    svgEl('line', { x1: pad.l, x2: w - pad.r, y1: y, y2: y, class: 'grid-line' }, s);
    svgEl('text', { x: pad.l - 8, y: y + 3.5, class: 'axis-label', 'text-anchor': 'end' }, s)
      .textContent = yFmt(v);
  }

  const bandW = iw / categories.length;
  const usable = bandW * 0.66;
  const barW = stacked ? Math.min(usable, 30) : Math.min(usable / series.length - 3, 24);

  categories.forEach((cat, i) => {
    const cx = pad.l + bandW * i + bandW / 2;
    svgEl('text', { x: cx, y: h - 8, class: 'axis-label', 'text-anchor': 'middle' }, s)
      .textContent = cat;

    let acc = 0;
    series.forEach((se, si) => {
      const v = se.values[i] || 0;
      const x = stacked
        ? cx - barW / 2
        : cx - (series.length * (barW + 3)) / 2 + si * (barW + 3);
      const yTop = stacked ? Y(acc + v) : Y(v);
      const yBottom = stacked ? Y(acc) : pad.t + ih;
      const rect = svgEl('rect', {
        x, y: yTop, width: barW, height: Math.max(yBottom - yTop, 0.8),
        rx: stacked ? 0 : 2.5, fill: se.color, class: 'bar'
      }, s);
      attachTip(rect, `<b>${esc(cat)}</b><div class="t-sub">${esc(se.name)}: <b>${yFmt(v)}</b></div>`);
      acc += v;
    });
  });

  if (series.length > 1 && legendItems && !stacked) {
    legend(host, series.map((x) => ({ label: x.name, color: x.color })));
  }
}

function hBarChart(host, opts) {
  const { rows, labelWidth = 152, rowH = 30, valueFmt = fmtCompact, barColor = NEUTRAL } = opts;
  const height = Math.max(rows.length * rowH + 6, 40);
  const { s, w } = chartHost(host, height);
  const barArea = Math.max(w - labelWidth - 62, 50);
  const max = Math.max(...rows.map((r) => r.value), 1);

  rows.forEach((r, i) => {
    const y = i * rowH + 2;
    svgEl('text', { x: 0, y: y + 10, class: 'row-label' }, s).textContent = clip(r.label, 22);
    if (r.sub) svgEl('text', { x: 0, y: y + 22, class: 'row-sub' }, s).textContent = clip(r.sub, 30);

    const bw = Math.max((r.value / max) * barArea, 2);
    const rect = svgEl('rect', {
      x: labelWidth, y: y + 5, width: bw, height: 15, rx: 3,
      fill: r.color || barColor, class: 'bar'
    }, s);
    svgEl('text', {
      x: labelWidth + bw + 7, y: y + 16.5, class: 'bar-value'
    }, s).textContent = valueFmt(r.value);

    attachTip(rect, `<b>${esc(r.label)}</b>` +
      (r.sub ? `<div class="t-sub">${esc(r.sub)}</div>` : '') +
      `<div class="t-sub">${valueFmt(r.value)}</div>`);
  });
}

function table(host, columns, rows) {
  host.innerHTML = `<table><thead><tr>${columns.map((c) =>
    `<th${c.num ? ' class="num"' : ''}>${esc(c.label)}</th>`).join('')}</tr></thead>` +
    `<tbody>${rows.join('')}</tbody></table>`;
}

function empty(host, text) {
  host.innerHTML = `<p class="insight">${esc(text)}</p>`;
}

/* ---------------- sections ---------------- */

function renderHero() {
  const k = DATA.kpis;
  const sp = k.find((r) => r.platform === 'Spotify');
  const yt = k.find((r) => r.platform === 'YouTube');
  const total = (sp?.observations || 0) + (yt?.observations || 0);
  const queries = Object.keys(DATA.meta.query_row_counts).length;

  $('#heroMeta').innerHTML = [
    `<span class="chip">Period <b>${longDate(sp.first_date)} \u2013 ${longDate(sp.last_date)}</b></span>`,
    `<span class="chip">Chart weeks <b>${fmtInt(sp.chart_dates)}</b></span>`,
    `<span class="chip">Observations <b>${fmtInt(total)}</b></span>`,
    `<span class="chip">Artists <b>${fmtInt(DATA.meta.source_rows.artists)}</b></span>`,
    `<span class="chip">Business queries <b>${queries}</b></span>`
  ].join('');

  $('#footMeta').innerHTML =
    `Generated ${DATA.meta.generated_at.replace('T', ' ')}<br>` +
    `${fmtInt(total)} usable chart observations<br>` +
    `SQL: ${esc(DATA.meta.query_file)}`;
}

function kpiCard(label, value, sub, accent) {
  return `<article class="kpi" style="--accent:${accent || NEUTRAL}">
    <div class="kpi-label">${esc(label)}</div>
    <div class="kpi-value">${value}</div>
    <div class="kpi-sub">${sub}</div>
  </article>`;
}

function renderKpis() {
  const all = DATA.kpis;
  const rows = state.platform === 'All' ? all : all.filter((r) => r.platform === state.platform);
  const sp = all.find((r) => r.platform === 'Spotify');
  const yt = all.find((r) => r.platform === 'YouTube');
  const sum = (key) => rows.reduce((a, r) => a + r[key], 0);
  const accent = state.platform === 'All' ? NEUTRAL : COLORS[state.platform];

  const longevity = DATA.longevity_summary.filter((r) => activePlatforms().includes(r.platform));
  const medians = longevity.map((r) => Math.round(r.median_weeks)).join(' / ');
  const medianSub = longevity.map((r) => `${r.platform} ${Math.round(r.median_weeks)}w`).join(' \u00b7 ');

  const observations = sum('observations');
  const items = sum('items');
  const top10 = sum('items_with_top10');

  const cards = [
    kpiCard('Chart observations', fmtInt(observations),
      state.platform === 'All'
        ? `${fmtCompact(sp.observations)} Spotify \u00b7 ${fmtCompact(yt.observations)} YouTube`
        : `${state.platform} only \u00b7 all markets`, accent),
    kpiCard('Markets covered',
      state.platform === 'All' ? `${sp.markets} + ${yt.markets}` : fmtInt(rows[0].markets),
      state.platform === 'All' ? 'Spotify + YouTube charts' : 'chart markets', accent),
    kpiCard('Songs & videos tracked', fmtCompact(items),
      `${fmtInt(sp.items)} songs \u00b7 ${fmtInt(yt.items)} videos`,
      accent),
    kpiCard('Chart weeks', fmtInt(rows[0].chart_dates),
      `${longDate(rows[0].first_date)} \u2013 ${longDate(rows[0].last_date)}`, accent),
    kpiCard('Items reaching the top 10', fmtInt(top10),
      `${fmtCompact(sp.items_with_top10)} Spotify \u00b7 ${fmtCompact(yt.items_with_top10)} YouTube`,
      accent),
    kpiCard('Median chart lifetime',
      `<span>${medians}</span><small>weeks</small>`, medianSub, accent)
  ];

  $('#kpiGrid').innerHTML = cards.join('');
}

function renderWeekly() {
  const rows = DATA.weekly;
  const labels = rows.map((r) => dateLabel(r.chart_date));
  const series = activePlatforms().map((p) => ({
    name: p,
    color: COLORS[p],
    values: rows.map((r) => (p === 'Spotify' ? r.spotify_items : r.youtube_items))
  }));

  lineChart($('#weeklyChart'), { series, labels, height: 236, area: series.length === 1 });

  const avg = (arr) => arr.reduce((a, b) => a + b, 0) / Math.max(arr.length, 1);
  const parts = series.map((ser) => {
    const early = avg(ser.values.slice(0, 52));
    const late = avg(ser.values.slice(-52));
    const delta = ((late - early) / early) * 100;
    return `<b>${ser.name}</b> averages <b>${fmtInt(late)}</b> distinct items per week in the final year, ` +
      `${delta >= 0 ? 'up' : 'down'} <b>${Math.abs(delta).toFixed(1)}%</b> on the first year (${fmtInt(early)}).`;
  });
  $('#weeklyInsight').innerHTML = parts.join(' ');
}

function renderAnnual() {
  const rows = DATA.annual;
  const years = [...new Set(rows.map((r) => r.chart_year))].sort();
  const series = activePlatforms().map((p) => ({
    name: p,
    color: COLORS[p],
    values: years.map((y) => {
      const row = rows.find((r) => r.chart_year === y && r.platform === p);
      return row ? row.items : 0;
    })
  }));
  barChart($('#annualChart'), { categories: years.map(String), series, height: 228 });
}

function renderNewItems() {
  const rows = DATA.new_items;
  const years = [...new Set(rows.map((r) => r.chart_year))].sort();
  const series = activePlatforms().map((p) => ({
    name: p,
    color: COLORS[p],
    values: years.map((y) => {
      const row = rows.find((r) => r.chart_year === y && r.platform === p);
      return row ? row.new_items : 0;
    })
  }));
  barChart($('#newItemsChart'), { categories: years.map(String), series, height: 228 });
}

function renderSeason() {
  const host = $('#seasonHeatmap');
  host.innerHTML = '';
  const rows = activeRows(DATA.seasonality);
  const years = [...new Set(rows.map((r) => r.chart_year))].sort();

  const cells = [];
  years.forEach((y) => {
    for (let m = 1; m <= 12; m++) {
      const hit = rows.filter((r) => r.chart_year === y && r.chart_month === m);
      const dates = hit.reduce((a, r) => a + r.chart_dates, 0);
      const weighted = hit.reduce((a, r) => a + r.avg_items * r.chart_dates, 0);
      cells.push({ y, m, value: dates ? weighted / dates : null });
    }
  });

  const values = cells.map((c) => c.value).filter((v) => v != null);
  const lo = Math.min(...values);
  const hi = Math.max(...values);

  host.appendChild(Object.assign(document.createElement('div'), { className: 'hm-year' }));
  MONTHS.forEach((m) => host.appendChild(
    Object.assign(document.createElement('div'), { className: 'hm-month', textContent: m })));

  cells.forEach((c) => {
    if (c.m === 1) host.appendChild(
      Object.assign(document.createElement('div'), { className: 'hm-year', textContent: c.y }));

    const cell = document.createElement('div');
    cell.className = 'hm-cell' + (c.value == null ? ' empty' : '');
    if (c.value != null) {
      const t = hi === lo ? 0.6 : (c.value - lo) / (hi - lo);
      cell.style.background = `rgba(30,215,96,${(0.07 + 0.78 * t).toFixed(3)})`;
      attachTip(cell, `<b>${MONTHS[c.m - 1]} ${c.y}</b>` +
        `<div class="t-sub">${fmtInt(c.value)} distinct items per chart date</div>`);
    }
    host.appendChild(cell);
  });

  host.insertAdjacentHTML('beforeend',
    `<div class="hm-scale" style="grid-column:1/-1">
       <span>${fmtInt(lo)}</span><i></i><span>${fmtInt(hi)} items / chart date</span>
     </div>`);

  // month ranking from complete years only
  const complete = years.filter((y) => y !== years[0]);
  const monthly = MONTHS.map((_, i) => {
    const hit = cells.filter((c) => c.m === i + 1 && complete.includes(c.y) && c.value != null);
    return hit.length ? hit.reduce((a, c) => a + c.value, 0) / hit.length : null;
  });
  const ranked = monthly.map((v, i) => ({ v, m: i })).filter((x) => x.v != null)
    .sort((a, b) => b.v - a.v);
  const top = ranked[0];
  const bottom = ranked[ranked.length - 1];

  $('#seasonInsight').innerHTML =
    `<b>${LONG_MONTHS[top.m]}</b> carries the broadest chart (${fmtInt(top.v)} distinct items per chart date), ` +
    `while <b>${LONG_MONTHS[bottom.m]}</b> is the thinnest (${fmtInt(bottom.v)}), ` +
    `a ${(((top.v - bottom.v) / bottom.v) * 100).toFixed(1)}% swing. ` +
    `<span style="color:var(--dim)">2018 is excluded from this ranking because the dataset starts in May.</span>`;
}

function renderLongevity() {
  const order = ['1 week', '2-4', '5-12', '13-26', '27-52', '53+'];
  const rows = activeRows(DATA.longevity_buckets);
  const series = activePlatforms().map((p) => {
    const own = rows.filter((r) => r.platform === p);
    const total = own.reduce((a, r) => a + r.items, 0);
    return {
      name: p,
      color: COLORS[p],
      values: order.map((band) => {
        const row = own.find((r) => r.lifetime_band === band);
        return row ? (row.items / total) * 100 : 0;
      })
    };
  });

  barChart($('#longevityChart'), {
    categories: order.map((b) => (b === '1 week' ? '1 wk' : b)),
    series, height: 230, yFmt: (v) => fmtPct(v), yTicks: 4
  });

  const summary = DATA.longevity_summary.filter((r) => activePlatforms().includes(r.platform));
  $('#longevityInsight').innerHTML = summary.map((s) => {
    const own = rows.filter((r) => r.platform === s.platform);
    const one = own.find((r) => r.lifetime_band === '1 week');
    const total = own.reduce((a, r) => a + r.items, 0);
    const long = own.find((r) => r.lifetime_band === '53+');
    return `<b>${s.platform}</b>: median <b>${Math.round(s.median_weeks)} weeks</b>, ` +
      `${((one.items / total) * 100).toFixed(0)}% last a single week, ` +
      `<b>${fmtInt(long.items)}</b> items passed 53 weeks (max ${fmtInt(s.max_weeks)}).`;
  }).join(' ');
}

function renderConcentration() {
  const rows = activeRows(DATA.concentration);
  const topNs = [...new Set(rows.map((r) => r.top_n))].sort((a, b) => a - b);
  const labels = topNs.map((n) => (n >= 1000 ? 'Top ' + (n / 1000) + 'K' : 'Top ' + n));
  const series = activePlatforms().map((p) => ({
    name: p,
    color: COLORS[p],
    values: topNs.map((n) => {
      const row = rows.find((r) => r.top_n === n && r.platform === p);
      return row ? row.cumulative_pct : 0;
    })
  }));

  lineChart($('#concentrationChart'), {
    series, labels, height: 230, yFmt: (v) => fmtPct(v), area: false, yTicks: 4
  });

  $('#concentrationInsight').innerHTML = series.map((ser) => {
    const p = ser.name;
    const row1k = DATA.concentration.find((r) => r.platform === p && r.top_n === 1000);
    const pct = (1000 / row1k.total_items) * 100;
    return `The top <b>1,000 ${p}</b> items \u2014 ${pct.toFixed(1)}% of ${fmtInt(row1k.total_items)} \u2014 ` +
      `hold <b>${fmtPct(row1k.cumulative_pct)}</b> of all chart weeks.`;
  }).join(' ');
}

function renderTopSongs() {
  const rows = activeRows(DATA.top_songs).sort((a, b) => b.chart_weeks - a.chart_weeks).slice(0, 20);
  table($('#topSongsTable'),
    [{ label: '#' }, { label: 'Platform' }, { label: 'Song' },
     { label: 'Weeks', num: true }, { label: 'Markets', num: true }, { label: 'Best', num: true }],
    rows.map((r, i) => `<tr>
      <td class="rank">${i + 1}</td>
      <td>${platformTag(r.platform)}</td>
      <td>${esc(r.title)}<span class="cell-sub">${esc(r.artists || 'Unknown artist')}</span></td>
      <td class="num">${fmtInt(r.chart_weeks)}</td>
      <td class="num">${fmtInt(r.markets)}</td>
      <td class="num">${fmtInt(r.best_rank)}</td>
    </tr>`));
}

function renderArtists() {
  const rows = activeRows(DATA.artists).sort((a, b) => b.chart_weeks - a.chart_weeks).slice(0, 10);
  hBarChart($('#artistChart'), {
    rows: rows.map((r) => ({
      label: r.artist_name,
      sub: `${r.markets} markets \u00b7 ${r.items} items`,
      value: r.chart_weeks,
      color: COLORS[r.platform]
    })),
    labelWidth: 168, rowH: 32, valueFmt: (v) => fmtInt(v) + ' wk'
  });

  const detail = activeRows(DATA.artists).sort((a, b) => b.chart_weeks - a.chart_weeks).slice(0, 20);
  table($('#artistTable'),
    [{ label: 'Artist' }, { label: 'Platform' }, { label: 'Items', num: true },
     { label: 'Weeks', num: true }, { label: 'Markets', num: true }, { label: 'Best', num: true }],
    detail.map((r) => `<tr>
      <td>${esc(r.artist_name)}<span class="cell-sub">avg rank ${r.avg_rank}</span></td>
      <td>${platformTag(r.platform)}</td>
      <td class="num">${fmtInt(r.items)}</td>
      <td class="num">${fmtInt(r.chart_weeks)}</td>
      <td class="num">${fmtInt(r.markets)}</td>
      <td class="num">${fmtInt(r.best_rank)}</td>
    </tr>`));
}

function renderMarkets() {
  const rows = activeRows(DATA.markets);
  const spAll = DATA.markets.filter((r) => r.platform === 'Spotify');
  const sampled = spAll.filter((r) => r.chart_dates < 400).length;
  const weekly = spAll.filter((r) => r.chart_dates >= 400)
    .map((r) => MARKET_NAMES[r.market_code] || r.market_code.toUpperCase());

  $('#coverageCallout').innerHTML =
    `<span class="ico">&#9670;</span>
     <div><strong>Coverage is not uniform \u2014 compare weeks observed, not row counts.</strong>
     ${sampled} of ${spAll.length} Spotify markets are sampled at 50\u2013100 chart weeks across eight years
     (roughly monthly); only the ${weekly.join(' and ')} charts are weekly. All
     ${DATA.markets.filter((r) => r.platform === 'YouTube').length} YouTube markets are weekly.
     Chart lifetime figures for Spotify items in sampled markets are therefore thinner by construction.</div>`;

  const sorted = [...rows].sort((a, b) => {
    if (a.platform !== b.platform) return a.platform === 'Spotify' ? -1 : 1;
    return b.observations - a.observations;
  });

  table($('#marketTable'),
    [{ label: 'Market' }, { label: 'Platform' }, { label: 'Weeks obs.', num: true },
     { label: 'Items', num: true }, { label: 'Top-10 obs.', num: true }],
    sorted.map((r) => {
      const name = MARKET_NAMES[r.market_code] || r.market_code.toUpperCase();
      const cls = r.chart_dates >= 400 ? 'full' : 'thin';
      return `<tr>
        <td>${esc(name)}<span class="cell-sub">${esc(r.market_code)}</span></td>
        <td>${platformTag(r.platform)}</td>
        <td class="num"><span class="coverage-pill ${cls}">${fmtInt(r.chart_dates)}</span></td>
        <td class="num">${fmtInt(r.items)}</td>
        <td class="num">${fmtCompact(r.top10_observations)}</td>
      </tr>`;
    }));

  renderLeaders();
}

function renderLeaders() {
  const picker = $('#marketPicker');
  const markets = [...new Set(DATA.market_leaders.map((r) => r.market_code))].sort((a, b) => {
    if (a === 'global') return -1;
    if (b === 'global') return 1;
    return (MARKET_NAMES[a] || a).localeCompare(MARKET_NAMES[b] || b);
  });

  if (!markets.includes(state.market)) state.market = markets[0];

  picker.innerHTML = `<label class="hint" for="marketSelect">Market</label>
    <select id="marketSelect">${markets.map((m) =>
      `<option value="${m}"${m === state.market ? ' selected' : ''}>${esc(MARKET_NAMES[m] || m.toUpperCase())}</option>`).join('')}
    </select>`;

  $('#marketSelect').addEventListener('change', (ev) => {
    state.market = ev.target.value;
    renderLeaders();
  });

  const rows = DATA.market_leaders.filter((r) =>
    r.market_code === state.market && activePlatforms().includes(r.platform));

  if (!rows.length) { empty($('#leaderTable'), 'No leader data for this market and platform filter.'); return; }

  table($('#leaderTable'),
    [{ label: 'Song' }, { label: 'Platform' }, { label: 'Weeks', num: true }, { label: 'Best', num: true }],
    rows.map((r) => `<tr>
      <td>${esc(r.title)}<span class="cell-sub">${esc(r.artists || 'Unknown artist')}</span></td>
      <td>${platformTag(r.platform)}</td>
      <td class="num">${fmtInt(r.weeks)}</td>
      <td class="num">${fmtInt(r.best_rank)}</td>
    </tr>`));
}

function renderNumberOnes() {
  const rows = activeRows(DATA.number_ones).sort((a, b) => b.no1_market_weeks - a.no1_market_weeks).slice(0, 10);
  if (!rows.length) { empty($('#numberOneChart'), 'No number-one observations for this filter.'); return; }

  hBarChart($('#numberOneChart'), {
    rows: rows.map((r) => ({
      label: r.title,
      sub: `${r.artists || 'Unknown'} \u00b7 ${r.markets} markets`,
      value: r.no1_market_weeks,
      color: COLORS[r.platform]
    })),
    labelWidth: 150, rowH: 32, valueFmt: (v) => fmtInt(v) + ' wk'
  });

  const overview = DATA.number_ones_overview.filter((r) => activePlatforms().includes(r.platform));
  $('#numberOneInsight').innerHTML = overview.map((o) =>
    `<b>${o.platform}</b>: ${fmtInt(o.items)} items have held a #1 position across ` +
    `<b>${fmtInt(o.no1_market_weeks)}</b> market-weeks in total; the single strongest ` +
    `occupies <b>${fmtInt(o.max_weeks)}</b> of them.`).join(' ');
}

function renderViewsBand() {
  const rows = DATA.views_by_rank_band;
  const categories = rows.map((r) => r.rank_band);
  barChart($('#viewsBandChart'), {
    categories,
    series: [{ name: 'YouTube', color: COLORS.YouTube, values: rows.map((r) => r.median_views) }],
    height: 230, legendItems: false
  });

  const top = rows[0];
  const bottom = rows[rows.length - 1];
  const multiple = top.median_views / bottom.median_views;
  $('#viewsBandInsight').innerHTML =
    `Median weekly views fall from <b>${fmtCompact(top.median_views)}</b> in ranks 1\u201310 to ` +
    `<b>${fmtCompact(bottom.median_views)}</b> in ranks 51\u2013100 \u2014 a <b>${multiple.toFixed(1)}\u00d7</b> gap. ` +
    `Attention decays steadily rather than falling off a cliff, so mid-chart placements still deliver meaningful volume.`;
}

function renderOverlap() {
  const s = DATA.cross_platform_summary[0];
  const share = (s.matched_credits / s.spotify_credits) * 100;

  $('#overlapBlock').innerHTML = `
    <div class="overlap-side">
      <div class="big" style="color:${COLORS.Spotify}">${fmtInt(s.spotify_credits)}</div>
      <div class="cap">Spotify song credits</div>
    </div>
    <div class="overlap-mid">
      <div class="big">${fmtInt(s.matched_credits)}</div>
      <div class="cap">${share.toFixed(1)}% on both</div>
    </div>
    <div class="overlap-side">
      <div class="big" style="color:${COLORS.YouTube}">${fmtInt(s.youtube_credits)}</div>
      <div class="cap">YouTube song credits</div>
    </div>
    <div class="overlap-bar"><i style="width:${share.toFixed(1)}%"></i></div>`;

  table($('#overlapTable'),
    [{ label: 'Song' }, { label: 'Spotify wk', num: true }, { label: 'YouTube wk', num: true },
     { label: 'SP best', num: true }, { label: 'YT best', num: true }],
    DATA.cross_platform_top.map((r) => `<tr>
      <td>${esc(r.title)}<span class="cell-sub">${esc(r.artists || 'Unknown artist')}</span></td>
      <td class="num">${fmtInt(r.spotify_weeks)}</td>
      <td class="num">${fmtInt(r.youtube_weeks)}</td>
      <td class="num">${fmtInt(r.spotify_best)}</td>
      <td class="num">${fmtInt(r.youtube_best)}</td>
    </tr>`));
}

function renderLag() {
  const order = ['0-30 days', '31-90', '91-180', '181-365', '1yr+'];
  const rows = activeRows(DATA.release_lag_buckets);
  const series = activePlatforms().map((p) => {
    const own = rows.filter((r) => r.platform === p);
    const total = own.reduce((a, r) => a + r.items, 0);
    return {
      name: p, color: COLORS[p],
      values: order.map((band) => {
        const row = own.find((r) => r.lag_band === band);
        return row ? (row.items / total) * 100 : 0;
      })
    };
  });

  barChart($('#lagChart'), {
    categories: order.map((b) => (b === '0-30 days' ? '0-30d' : b === '1yr+' ? '1yr+' : b + 'd')),
    series, height: 230, yFmt: (v) => fmtPct(v)
  });

  $('#lagInsight').innerHTML = activePlatforms().map((p) => {
    const own = rows.filter((r) => r.platform === p);
    const total = own.reduce((a, r) => a + r.items, 0);
    const fast = own.find((r) => r.lag_band === '0-30 days');
    return `<b>${p}</b>: <b>${((fast.items / total) * 100).toFixed(0)}%</b> of charting items arrive within 30 days of release.`;
  }).join(' ');

  const years = [...new Set(DATA.release_lag_by_year.map((r) => r.chart_year))].sort();
  const lseries = activePlatforms().map((p) => ({
    name: p, color: COLORS[p],
    values: years.map((y) => {
      const row = DATA.release_lag_by_year.find((r) => r.platform === p && r.chart_year === y);
      return row ? row.median_days : 0;
    })
  }));

  lineChart($('#lagYearChart'), {
    series: lseries, labels: years.map(String), height: 230, area: false,
    yFmt: (v) => fmtInt(v) + 'd', yTicks: 4
  });
}

function renderCreators() {
  hBarChart($('#writersChart'), {
    rows: DATA.writers.map((r) => ({
      label: r.name, sub: 'songwriter', value: r.charting_songs, color: '#8B7CF6'
    })),
    labelWidth: 150, rowH: 26, valueFmt: (v) => fmtInt(v) + ' songs'
  });

  hBarChart($('#producersChart'), {
    rows: DATA.producers.map((r) => ({
      label: r.name, sub: 'producer', value: r.charting_songs, color: '#4FB6C9'
    })),
    labelWidth: 150, rowH: 26, valueFmt: (v) => fmtInt(v) + ' songs'
  });

  table($('#videosTable'),
    [{ label: 'Video' }, { label: 'Total views', num: true }, { label: 'Peak week', num: true },
     { label: 'Weeks', num: true }, { label: 'Markets', num: true }],
    DATA.top_videos.map((r) => `<tr>
      <td>${esc(r.title)}<span class="cell-sub">${esc(r.artists || 'Unknown artist')}</span></td>
      <td class="num">${fmtCompact(r.total_views)}</td>
      <td class="num">${fmtCompact(r.peak_week_views)}</td>
      <td class="num">${fmtInt(r.chart_weeks)}</td>
      <td class="num">${fmtInt(r.markets)}</td>
    </tr>`));
}

function renderEntries() {
  const statuses = [
    { key: 'NEW_ENTRY', label: 'New entry', color: '#1ED760' },
    { key: 'RE_ENTRY', label: 'Re-entry', color: '#5AA9E6' },
    { key: 'MOVED_UP', label: 'Moved up', color: '#9AA7B8' },
    { key: 'MOVED_DOWN', label: 'Moved down', color: '#4A5561' },
    { key: 'NO_CHANGE', label: 'No change', color: '#2B323B' }
  ];
  const rows = DATA.entries;
  const years = [...new Set(rows.map((r) => r.chart_year))].sort();

  barChart($('#entriesChart'), {
    categories: years.map(String),
    series: statuses.map((st) => ({
      name: st.label, color: st.color,
      values: years.map((y) => {
        const row = rows.find((r) => r.chart_year === y && r.entry_status === st.key);
        return row ? row.observations : 0;
      })
    })),
    height: 250, stacked: true
  });
  legend($('#entriesChart'), statuses.map((st) => ({ label: st.label, color: st.color })));

  const yearStats = years.map((y) => {
    const own = rows.filter((r) => r.chart_year === y);
    const total = own.reduce((a, r) => a + r.observations, 0);
    const fresh = own.filter((r) => r.entry_status === 'NEW_ENTRY' || r.entry_status === 'RE_ENTRY')
      .reduce((a, r) => a + r.observations, 0);
    return { y, share: (fresh / total) * 100 };
  });
  const first = yearStats[0];
  const last = yearStats[yearStats.length - 1];
  $('#entriesInsight').innerHTML =
    `Only <b>${first.share.toFixed(1)}%</b> of Spotify chart rows in ${first.y} were a new or returning entry, ` +
    `against <b>${last.share.toFixed(1)}%</b> in ${last.y}. The rest of the chart is music that was already there ` +
    `and simply moved \u2014 chart space is dominated by incumbents.`;
}

function renderQuality() {
  table($('#qualityTable'),
    [{ label: 'Platform' }, { label: 'Observations', num: true }, { label: 'Excluded', num: true },
     { label: 'Future rel. dates nulled', num: true }, { label: 'Repeated obs.', num: true },
     { label: 'Missing ID', num: true }, { label: 'Missing release', num: true }],
    DATA.data_quality.map((r) => `<tr>
      <td>${platformTag(r.platform)}</td>
      <td class="num">${fmtInt(r.observations)}</td>
      <td class="num">${fmtInt(r.unusable)}</td>
      <td class="num">${fmtInt(r.future_release_dates)}</td>
      <td class="num">${fmtInt(r.repeated_observations)}</td>
      <td class="num">${fmtInt(r.missing_item_id)}</td>
      <td class="num">${fmtInt(r.missing_release_date)}</td>
    </tr>`));

  const q = DATA.data_quality;
  const sp = q.find((r) => r.platform === 'Spotify');
  const yt = q.find((r) => r.platform === 'YouTube');

  $('#methodNotes').innerHTML = [
    `<b>Streams and views are never combined.</b> Spotify streams and YouTube views are different measures; ` +
    `the unified view keeps them in separate columns and this dashboard never adds them.`,
    `<b>Sampled Spotify markets.</b> 35 of 38 Spotify markets carry 50\u2013100 chart weeks over eight years; ` +
    `only Global and T\u00fcrkiye are weekly. YouTube is weekly in all 44 markets.`,
    `<b>Chart rank is platform-specific.</b> Every source chart is full (200 Spotify / 100 YouTube rows), ` +
    `so mean rank is a fixed 100.5 / 50.5 and is not reported as a finding.`,
    `<b>Excluded rows.</b> ${fmtInt(yt.unusable)} YouTube observations lacked a usable video ID and are dropped; ` +
    `${fmtInt(sp.future_release_dates + yt.future_release_dates)} observations had release dates after the chart date ` +
    `or before 1900 and are nulled in the clean layer.`,
    `<b>Cross-platform matching is a lower bound.</b> It requires identical normalised title and artist credit, ` +
    `so remixes, features and re-titles are not reconciled.`,
    `<b>Views are weekly reported values summed across chart observations</b>, not unique viewers.`,
    `<b>Not in the source data:</b> genre, audio features, brand suitability, licensing status and advertising ` +
    `permission. Chart presence does not establish permission to use music.`
  ].map((t) => `<li>${t}</li>`).join('');
}

/* ---------------- boot ---------------- */

function renderAll() {
  const jobs = [
    ['hero', renderHero], ['kpis', renderKpis], ['weekly', renderWeekly],
    ['annual', renderAnnual], ['newItems', renderNewItems], ['season', renderSeason],
    ['longevity', renderLongevity], ['concentration', renderConcentration],
    ['topSongs', renderTopSongs], ['artists', renderArtists], ['markets', renderMarkets],
    ['numberOnes', renderNumberOnes], ['viewsBand', renderViewsBand],
    ['overlap', renderOverlap], ['lag', renderLag], ['creators', renderCreators],
    ['entries', renderEntries], ['quality', renderQuality]
  ];

  jobs.forEach(([name, fn]) => {
    try { fn(); } catch (err) {
      console.error(`[dashboard] ${name} failed`, err);
    }
  });
}

function buildNav() {
  const links = [
    ['s-trend', 'Trend'], ['s-longevity', 'Longevity'], ['s-artists', 'Artists'],
    ['s-markets', 'Markets'], ['s-platforms', 'Platforms'], ['s-velocity', 'Velocity'],
    ['s-creators', 'Creators'], ['s-intake', 'Intake'], ['s-quality', 'Quality']
  ];
  $('#sectionNav').innerHTML = links.map(([id, label]) =>
    `<a href="#${id}">${label}</a>`).join('');
}

function bindControls() {
  $$('.seg').forEach((btn) => {
    btn.addEventListener('click', () => {
      state.platform = btn.dataset.platform;
      $$('.seg').forEach((b) => b.classList.toggle('is-active', b === btn));
      renderAll();
    });
  });

  let timer = null;
  window.addEventListener('resize', () => {
    clearTimeout(timer);
    timer = setTimeout(renderAll, 180);
  });
}

async function init() {
  buildNav();
  bindControls();

  try {
    const res = await fetch('data/dashboard.json', { cache: 'no-store' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    DATA = await res.json();
  } catch (err) {
    $('#main').innerHTML =
      `<div class="callout"><span class="ico">&#9670;</span><div>
        <strong>Dashboard data not found.</strong> Run
        <code>python python/export_dashboard_data.py</code> to generate
        <code>dashboard/data/dashboard.json</code>, then reload this page over a local web server
        (<code>python -m http.server</code>), not from the file system.
        <br><span style="color:var(--dim)">${esc(err.message)}</span>
      </div></div>`;
    return;
  }

  renderAll();
}

init();
