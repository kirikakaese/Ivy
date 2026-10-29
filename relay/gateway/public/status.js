// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
"use strict";

const $ = (id) => document.getElementById(id);
const headlines = {
  ok: "All good",
  maintenance: "Maintenance",
  degraded: "Some trouble",
  down: "Something isn't working",
  unknown: "Checking…",
  error: "Status unavailable",
};
const chipText = { ok: "Working", maintenance: "Maintenance", degraded: "Some trouble", down: "Down", unknown: "Unknown" };
const dayColor = { ok: "var(--ok)", maintenance: "var(--maint)", degraded: "var(--warn)", down: "var(--bad)", none: "var(--none)" };
const stepText = {
  investigating: "Investigating", identified: "Identified", monitoring: "Monitoring", resolved: "Resolved",
  scheduled: "Scheduled", in_progress: "In progress", completed: "Completed", posted: "Posted", removed: "Removed",
};
const kindText = { incident: "Incident", maintenance: "Maintenance", notice: "Notice" };
const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeZone: "UTC" });
const timeFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });
const percent = new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 });
let checked = null;
// Services whose 90 days are open, kept across refreshes.
const openServices = new Set();
const hourFormat = new Intl.DateTimeFormat(undefined, { hour: "numeric" });
let marked = [];

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === "class") node.className = value;
    else node.setAttribute(key, value);
  }
  for (const child of children) {
    if (child != null) node.append(child);
  }
  return node;
}

function ago(value) {
  const seconds = Math.max(0, (Date.now() - new Date(value).getTime()) / 1000);
  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
  return `${Math.floor(seconds / 3600)} h ago`;
}

function renderPost(post) {
  const classes = ["post", post.kind, post.impact || ""].join(" ");
  const meta = [kindText[post.kind]];
  if (post.kind === "maintenance" && post.starts) {
    meta.push(`${timeFormat.format(new Date(post.starts))} – ${timeFormat.format(new Date(post.ends))}`);
  }
  if (post.components && post.components.length) meta.push(post.components.join(", "));
  const updates = el("ol");
  for (const update of [...post.updates].reverse()) {
    updates.append(el("li", {},
      el("b", {}, stepText[update.step] || update.step),
      el("time", { datetime: update.time }, timeFormat.format(new Date(update.time))),
      update.message ? el("div", {}, update.message) : null));
  }
  return el("article", { class: classes },
    el("h3", {}, post.title),
    el("p", { class: "meta" }, meta.join(" · ")),
    updates);
}

// Day bars: green, fading into the day's problem colour at the top; the
// longer the problem lasted, the further down it reaches.
function dayBackground(day) {
  const m = day.minutes;
  if (!m || day.status === "none" || day.status === "ok") return dayColor[day.status] || dayColor.none;
  const total = m.ok + m.maintenance + m.degraded + m.down;
  const share = ((m.maintenance + m.degraded + m.down) / total) * 100;
  if (share >= 50) return dayColor[day.status];
  const reach = Math.max(share, 14);
  return `linear-gradient(to top, var(--ok) 0%, var(--ok) ${Math.max(100 - reach * 2.2, 0)}%, ${dayColor[day.status]} 100%)`;
}

function duration(minutes) {
  const h = Math.floor(minutes / 60), min = minutes % 60;
  return h ? (min ? `${h} h ${min} min` : `${h} h`) : `${min} min`;
}

function daySummary(day) {
  const m = day.minutes;
  if (!m) return "No data";
  const parts = [];
  if (m.down) parts.push(`${duration(m.down)} down`);
  if (m.degraded) parts.push(`${duration(m.degraded)} some trouble`);
  if (m.maintenance) parts.push(`${duration(m.maintenance)} maintenance`);
  const total = m.ok + m.maintenance + m.degraded + m.down;
  if (!parts.length) return "Working all day";
  parts.push(`${percent.format(((total - m.down) / total) * 100)} % up`);
  return parts.join(" · ");
}

// The incidents and maintenance that touched each day (UTC), for one
// service by its name or for all.
function postsByDay(service) {
  const byDay = new Map();
  for (const post of marked) {
    if (service && !post.components.includes(service)) continue;
    const start = new Date(post.kind === "maintenance" && post.starts ? post.starts : post.created);
    let end = post.closed ? new Date(post.closed) : new Date();
    if (post.kind === "maintenance" && post.ends && new Date(post.ends) < end) end = new Date(post.ends);
    for (let day = new Date(start.toISOString().slice(0, 10) + "T00:00:00Z"); day <= end; day.setUTCDate(day.getUTCDate() + 1)) {
      const key = day.toISOString().slice(0, 10);
      if (!byDay.has(key)) byDay.set(key, []);
      byDay.get(key).push(post);
    }
  }
  return byDay;
}

function markClass(post) {
  return post.kind === "maintenance" ? "maintenance" : post.impact === "major" ? "down" : "degraded";
}

// Bars for 90 days, with a mark under days that had an incident or
// maintenance.
function renderDays(container, marks, days, label, service) {
  const byDay = postsByDay(service);
  container.replaceChildren(...days.map((day) => {
    const posts = byDay.get(day.date) || [];
    const titles = posts.map((post) => `${kindText[post.kind]}: ${post.title}`);
    const span = el("span", { "aria-label": [`${dateFormat.format(new Date(day.date + "T00:00:00Z"))}: ${daySummary(day)}`, ...titles].join(". ") });
    span.style.background = dayBackground(day);
    span.ivyDay = day;
    span.ivyLabel = label;
    span.ivyPosts = posts;
    return span;
  }));
  marks.replaceChildren(...days.map((day) => {
    const posts = byDay.get(day.date) || [];
    if (!posts.length) return el("span");
    const worst = posts.find((post) => markClass(post) === "down") || posts.find((post) => markClass(post) === "degraded") || posts[0];
    return el("span", {}, el("i", { class: markClass(worst) }));
  }));
}

// A UTC hour of a day, in the visitor's time.
function localHour(date, hour) {
  return hourFormat.format(new Date(Date.parse(date + "T00:00:00Z") + hour * 3600000));
}

function zoneName(date) {
  const part = new Intl.DateTimeFormat(undefined, { timeZoneName: "short" }).formatToParts(new Date(date + "T12:00:00Z")).find((p) => p.type === "timeZoneName");
  return part ? part.value : "";
}

// The tooltip: the day, what happened and when, hour by hour (UTC).
function showTip(span) {
  const day = span.ivyDay, tip = $("tip");
  const today = new Date().toISOString().slice(0, 10);
  const nowHour = new Date().getUTCHours();
  const hours = new Map((day.hours || []).map((h) => [h.hour, h]));
  const line = el("div", { class: "line" });
  for (let hour = 0; hour < 24; hour++) {
    const cell = el("i");
    const trouble = hours.get(hour);
    if (!day.minutes || (day.date === today && hour > nowHour)) {
      cell.className = "none";
    } else if (trouble) {
      const worst = trouble.down ? "down" : trouble.degraded ? "degraded" : "maintenance";
      cell.style.background = dayColor[worst];
      const minutes = (trouble.down || 0) + (trouble.degraded || 0) + (trouble.maintenance || 0);
      cell.style.opacity = String(0.45 + 0.55 * Math.min(1, minutes / 60));
    } else {
      cell.style.background = dayColor.ok;
    }
    line.append(cell);
  }
  const title = dateFormat.format(new Date(day.date + "T00:00:00Z")) + (span.ivyLabel ? ` · ${span.ivyLabel}` : "");
  const ticks = [0, 6, 12, 18, 24].map((hour) => el("span", {}, localHour(day.date, hour)));
  tip.replaceChildren(
    el("b", {}, title),
    el("span", {}, daySummary(day)),
    line,
    el("div", { class: "hours" }, ...ticks),
    el("span", { class: "zone" }, `Your time (${zoneName(day.date)})`),
    ...span.ivyPosts.map((post) => el("span", { class: `post-line ${markClass(post)}` }, `${kindText[post.kind]}: ${post.title}`)));
  tip.hidden = false;
  const bar = span.getBoundingClientRect(), box = tip.getBoundingClientRect();
  const left = Math.min(Math.max(bar.left + bar.width / 2 - box.width / 2, 12), window.innerWidth - box.width - 12);
  const above = bar.top - box.height - 8;
  tip.style.left = `${left}px`;
  tip.style.top = `${above > 8 ? above : bar.bottom + 8}px`;
}

function hideTip() {
  $("tip").hidden = true;
}

document.addEventListener("pointerover", (event) => {
  if (event.target.ivyDay) showTip(event.target);
  else if (event.pointerType === "mouse") hideTip();
});
document.addEventListener("click", (event) => {
  if (event.target.ivyDay) showTip(event.target);
  else hideTip();
});
window.addEventListener("scroll", hideTip, { passive: true });

function uptime(days) {
  let up = 0, total = 0;
  for (const day of days) {
    const m = day.minutes;
    if (!m) continue;
    const minutes = m.ok + m.maintenance + m.degraded + m.down;
    up += minutes - m.down;
    total += minutes;
  }
  return total ? (up / total) * 100 : null;
}

// How the last 7 days went, for the summary of a folded service.
function lastWeek(days) {
  const week = days.slice(-7).map((day) => day.status);
  if (week.includes("down")) return { class: "down", text: "down this week" };
  if (week.includes("degraded")) return { class: "degraded", text: "trouble this week" };
  return null;
}

function renderService(c) {
  const days = el("div", { class: "days", role: "group", "aria-label": `${c.name}, status of each of the last 90 days` });
  const marks = el("div", { class: "marks", "aria-hidden": "true" });
  renderDays(days, marks, c.days || [], c.name, c.name);
  const up = uptime(c.days || []);
  const week = lastWeek(c.days || []);
  const summary = el("summary", {}, up == null ? "Last 90 days · no data yet" : `Last 90 days · ${percent.format(up)} % up`);
  if (week) summary.append(el("span", { class: `week ${week.class}` }, week.text));
  const details = el("details", { class: "service-days" },
    summary,
    days,
    marks,
    el("div", { class: "scale muted" }, el("span", {}, "90 days ago"), el("span", {}, "Today")));
  details.open = openServices.has(c.id);
  details.addEventListener("toggle", () => {
    if (details.open) openServices.add(c.id);
    else openServices.delete(c.id);
  });
  return el("li", {},
    el("span", { class: "name" }, c.name),
    el("span", { class: `chip ${c.status}` }, chipText[c.status] || c.status),
    el("span", { class: "desc" }, c.detail ? `${c.description} Now: ${c.detail}.` : c.description),
    details);
}

function renderPosts(container, posts) {
  container.replaceChildren(...posts.map(renderPost));
  container.hidden = posts.length === 0;
}

function metric(id, value, format) {
  $(id).textContent = value == null ? "–" : format(value);
  $(id).title = value == null ? "Not enough data yet" : "";
}

function render(data) {
  checked = data.checked;
  marked = data.marked || [];
  $("hero").dataset.status = data.status;
  $("headline").textContent = headlines[data.status] || data.status;
  $("message").textContent = data.message;
  document.title = `${headlines[data.status] || data.status} · Ivy Status`;

  renderPosts($("active"), data.active);
  renderPosts($("upcoming"), data.upcoming);
  renderPosts($("recent"), data.recent);
  $("recent-wrap").hidden = data.recent.length === 0;

  $("components").replaceChildren(...data.components.map(renderService));

  metric("m-uptime30", data.metrics.uptime30, (v) => `${percent.format(v)} %`);
  metric("m-uptime90", data.metrics.uptime90, (v) => `${percent.format(v)} %`);
  metric("m-wake", data.metrics.wakeMedianMs, (v) => (v < 1000 ? `${Math.round(v)} ms` : `${(v / 1000).toFixed(1)} s`));
  metric("m-accept", data.metrics.acceptance24h, (v) => `${percent.format(v)} %`);

  hideTip();
  renderDays($("days"), $("marks"), data.days, "", "");
  let known = 0, good = 0;
  for (const day of data.days) {
    if (day.status !== "none") known++;
    if (day.status === "ok" || day.status === "maintenance") good++;
  }
  $("uptime-days").textContent = known ? `${percent.format((good / known) * 100)} % of days without trouble` : "";
  tick();
}

function tick() {
  $("checked").textContent = checked ? `Checked ${ago(checked)}. The page updates by itself.` : "";
}

async function refresh() {
  try {
    const response = await fetch("status.json", { cache: "no-store" });
    if (!response.ok) throw new Error(response.statusText);
    render(await response.json());
  } catch {
    $("hero").dataset.status = "error";
    $("headline").textContent = headlines.error;
    $("message").textContent = "The status service didn't answer. If this lasts, Ivy Push may be down.";
  }
}

refresh();
setInterval(refresh, 60000);
setInterval(tick, 10000);
