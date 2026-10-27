// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
"use strict";

const $ = (id) => document.getElementById(id);
const number = new Intl.NumberFormat();
const timeFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });
const hourFormat = new Intl.DateTimeFormat(undefined, { hour: "2-digit" });
const statusText = { ok: "Operational", degraded: "Degraded", down: "Down", error: "Unreachable" };
const resultText = { sent: "Delivered", failed: "Rejected", unregistered: "Token gone" };
let lastChecked = null;
let lastHourly = null;

function ago(value) {
  if (!value) return "never";
  const seconds = Math.max(0, (Date.now() - new Date(value).getTime()) / 1000);
  if (seconds < 60) return "just now";
  const units = [["d", 86400], ["h", 3600], ["min", 60]];
  for (const [unit, size] of units) {
    if (seconds >= size) return `${Math.floor(seconds / size)} ${unit} ago`;
  }
  return "just now";
}

function duration(from) {
  const seconds = (Date.now() - new Date(from).getTime()) / 1000;
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days > 0) return `${days} d ${hours} h`;
  if (hours > 0) return `${hours} h ${minutes} min`;
  return `${minutes} min`;
}

function stamp(value) {
  return value ? `${timeFormat.format(new Date(value))} (${ago(value)})` : "never";
}

function setText(id, text) {
  $(id).textContent = text;
}

function list(container, title, items) {
  container.replaceChildren();
  container.hidden = items.length === 0;
  if (items.length === 0) return;
  if (title) {
    const heading = document.createElement("strong");
    heading.textContent = title;
    container.append(heading);
  }
  const ul = document.createElement("ul");
  for (const item of items) {
    const li = document.createElement("li");
    li.textContent = item;
    ul.append(li);
  }
  container.append(ul);
}

const svgNS = "http://www.w3.org/2000/svg";
function svg(name, attributes) {
  const element = document.createElementNS(svgNS, name);
  for (const [key, value] of Object.entries(attributes)) element.setAttribute(key, value);
  return element;
}

function drawChart(hourly) {
  const width = Math.max(280, $("chart").clientWidth || 720), height = 180, left = 32, bottom = 22, top = 8;
  const max = Math.max(1, ...hourly.map((h) => h.sent + h.failed + h.unregistered));
  const scale = (height - bottom - top) / max;
  const slot = (width - left) / hourly.length;
  const chart = svg("svg", { viewBox: `0 0 ${width} ${height}` });

  for (const fraction of [0, 0.5, 1]) {
    const y = height - bottom - fraction * max * scale;
    chart.append(svg("line", { x1: left, x2: width, y1: y, y2: y, class: "grid-line" }));
    const label = svg("text", { x: left - 6, y: y + 4, "text-anchor": "end", class: "axis" });
    label.textContent = number.format(Math.round(fraction * max));
    chart.append(label);
  }

  hourly.forEach((hour, index) => {
    const x = left + index * slot + slot * 0.15;
    const barWidth = slot * 0.7;
    let y = height - bottom;
    for (const [key, cls] of [["sent", "sent"], ["failed", "failed"], ["unregistered", "gone"]]) {
      const value = hour[key];
      if (!value) continue;
      const barHeight = Math.max(1, value * scale);
      y -= barHeight;
      const rect = svg("rect", { x, y, width: barWidth, height: barHeight, rx: 2, class: cls });
      const title = svg("title", {});
      title.textContent = `${hourFormat.format(new Date(hour.hour))}: ${value} ${resultText[key].toLowerCase()}`;
      rect.append(title);
      chart.append(rect);
    }
    if (index % (width < 500 ? 6 : 4) === 0) {
      const label = svg("text", { x: x + barWidth / 2, y: height - 6, "text-anchor": "middle", class: "axis" });
      label.textContent = hourFormat.format(new Date(hour.hour));
      chart.append(label);
    }
  });
  $("chart").replaceChildren(chart);
}

function drawEvents(events) {
  const body = $("events");
  body.replaceChildren();
  if (events.length === 0) {
    const row = body.insertRow();
    const cell = row.insertCell();
    cell.colSpan = 4;
    cell.className = "muted";
    cell.textContent = "No wake-ups yet.";
    return;
  }
  for (const event of events.slice(0, 25)) {
    const row = body.insertRow();
    const time = row.insertCell();
    time.className = "time";
    time.textContent = timeFormat.format(new Date(event.time));
    time.title = ago(event.time);
    const device = row.insertCell();
    device.className = "mono";
    device.textContent = event.device;
    const result = row.insertCell();
    result.className = `result ${event.kind}`;
    result.textContent = resultText[event.kind] || event.kind;
    const detail = row.insertCell();
    detail.className = "mono";
    detail.textContent = event.detail || "";
  }
}

function render(data) {
  lastChecked = data.checked;
  const pill = $("status-pill");
  pill.dataset.status = data.status;
  pill.textContent = statusText[data.status] || data.status;
  document.title = `${statusText[data.status] || data.status} · Ivy Push`;

  list($("problems"), "Needs attention", data.problems);
  list($("notes"), "", data.notes);

  const relay = data.relay;
  const pushes = data.pushes;
  setText("k-connections", relay.reachable ? number.format(relay.connections) : "–");
  setText("k-active", number.format(pushes.active24h));
  setText("k-active-hint", `woken in the last 24 h · ${number.format(pushes.active7d)} in 7 days`);
  setText("k-sent", number.format(pushes.sent24h));
  setText("k-sent-hint", `last ${ago(pushes.lastSuccess)}`);
  setText("k-failed", number.format(pushes.failed24h));
  setText("k-failed-hint", `${number.format(pushes.unregistered24h)} with an expired token`);
  $("k-failed").parentElement.classList.toggle("bad", pushes.failed24h > 0);

  setText("f-last-success", stamp(pushes.lastSuccess));
  setText("f-last-failure", stamp(pushes.lastFailure));
  setText("f-last-error", pushes.lastError || "none");
  setText("f-total-sent", number.format(pushes.totalSent));
  setText("f-total-failed", number.format(pushes.totalFailed));
  setText("f-since", timeFormat.format(new Date(pushes.since)));

  setText("f-relay", relay.reachable ? `Running${relay.version ? `, version ${relay.version}` : ""}` : "Not answering");
  setText("f-messages", relay.reachable ? number.format(relay.messages) : "–");
  setText("f-pushes", relay.reachable ? number.format(relay.pushes) : "–");
  setText("f-reconnections", relay.reachable ? number.format(relay.reconnections) : "–");
  setText("f-forbidden", relay.reachable ? number.format(relay.forbidden) : "–");
  setText("f-uptime", duration(pushes.started));
  setText("f-bundle", data.bundleId);

  lastHourly = pushes.hourly;
  drawChart(pushes.hourly);
  drawEvents(pushes.events);
}

async function refresh() {
  try {
    const response = await fetch("status.json", { cache: "no-store" });
    if (!response.ok) throw new Error(response.statusText);
    render(await response.json());
  } catch (error) {
    const pill = $("status-pill");
    pill.dataset.status = "error";
    pill.textContent = statusText.error;
    list($("problems"), "Needs attention", [`The gateway didn't answer: ${error.message}`]);
  }
  tick();
}

function tick() {
  setText("updated", lastChecked ? `Updated ${ago(lastChecked)}` : "");
}

setText("domain", location.host);
refresh();
setInterval(refresh, 30000);
setInterval(tick, 5000);
window.addEventListener("resize", () => {
  if (lastHourly) drawChart(lastHourly);
});
