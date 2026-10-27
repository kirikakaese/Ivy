// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
"use strict";

const $ = (id) => document.getElementById(id);
const headlines = {
  ok: "All good",
  degraded: "Some delays",
  down: "Instant notifications are down",
  unknown: "Checking…",
  error: "Status unavailable",
};
const dayText = { ok: "working", degraded: "some delays", down: "down", none: "no data" };
const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeZone: "UTC" });
let checked = null;

function ago(value) {
  const seconds = Math.max(0, (Date.now() - new Date(value).getTime()) / 1000);
  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
  return `${Math.floor(seconds / 3600)} h ago`;
}

function render(data) {
  checked = data.checked;
  $("hero").dataset.status = data.status;
  $("headline").textContent = headlines[data.status] || data.status;
  $("message").textContent = data.message;
  document.title = `${headlines[data.status] || data.status} · Ivy Push`;

  const days = $("days");
  days.replaceChildren();
  let known = 0, good = 0;
  for (const day of data.days) {
    const cell = document.createElement("span");
    cell.className = day.status;
    cell.title = `${dateFormat.format(new Date(day.date + "T00:00:00Z"))}: ${dayText[day.status] || day.status}`;
    days.append(cell);
    if (day.status !== "none") known++;
    if (day.status === "ok") good++;
  }
  $("uptime").textContent = known ? `${Math.round((good / known) * 1000) / 10} % of days without trouble` : "";
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
    $("message").textContent = "The relay didn't answer. If this lasts, it may be down.";
  }
}

refresh();
setInterval(refresh, 60000);
setInterval(tick, 10000);
