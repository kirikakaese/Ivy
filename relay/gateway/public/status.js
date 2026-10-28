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
const dayText = { ok: "working", maintenance: "maintenance", degraded: "some trouble", down: "down", none: "no data" };
const stepText = {
  investigating: "Investigating", identified: "Identified", monitoring: "Monitoring", resolved: "Resolved",
  scheduled: "Scheduled", in_progress: "In progress", completed: "Completed", posted: "Posted", removed: "Removed",
};
const kindText = { incident: "Incident", maintenance: "Maintenance", notice: "Notice" };
const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeZone: "UTC" });
const timeFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });
const percent = new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 });
let checked = null;

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
  if (post.components.length) meta.push(post.components.join(", "));
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
  $("hero").dataset.status = data.status;
  $("headline").textContent = headlines[data.status] || data.status;
  $("message").textContent = data.message;
  document.title = `${headlines[data.status] || data.status} · Ivy Status`;

  renderPosts($("active"), data.active);
  renderPosts($("upcoming"), data.upcoming);
  renderPosts($("recent"), data.recent);
  $("recent-wrap").hidden = data.recent.length === 0;

  $("components").replaceChildren(...data.components.map((c) => el("li", {},
    el("span", { class: "name" }, c.name),
    el("span", { class: `chip ${c.status}` }, chipText[c.status] || c.status),
    el("span", { class: "desc" }, c.detail ? `${c.description} Now: ${c.detail}.` : c.description))));

  metric("m-uptime30", data.metrics.uptime30, (v) => `${percent.format(v)} %`);
  metric("m-uptime90", data.metrics.uptime90, (v) => `${percent.format(v)} %`);
  metric("m-wake", data.metrics.wakeMedianMs, (v) => (v < 1000 ? `${Math.round(v)} ms` : `${(v / 1000).toFixed(1)} s`));
  metric("m-accept", data.metrics.acceptance24h, (v) => `${percent.format(v)} %`);

  const days = $("days");
  days.replaceChildren();
  let known = 0, good = 0;
  for (const day of data.days) {
    days.append(el("span", { class: day.status, title: `${dateFormat.format(new Date(day.date + "T00:00:00Z"))}: ${dayText[day.status] || day.status}` }));
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
