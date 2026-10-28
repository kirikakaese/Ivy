// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
"use strict";

const $ = (id) => document.getElementById(id);
const number = new Intl.NumberFormat();
const timeFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });
const hourFormat = new Intl.DateTimeFormat(undefined, { hour: "2-digit" });
const statusText = { ok: "Operational", maintenance: "Maintenance", degraded: "Degraded", down: "Down", unknown: "Unknown", error: "Unreachable" };
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
  document.title = `${statusText[data.status] || data.status} · Ivy Status Admin`;

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
  drawComponents(data.components || []);
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
// Status page posts

const chipText = { ok: "Working", maintenance: "Maintenance", degraded: "Some trouble", down: "Down", unknown: "Unknown" };
const stepText = {
  investigating: "Investigating", identified: "Identified", monitoring: "Monitoring", resolved: "Resolved",
  scheduled: "Scheduled", in_progress: "In progress", completed: "Completed", posted: "Posted", removed: "Removed",
};
const kindText = { incident: "Incident", maintenance: "Maintenance", notice: "Notice" };
let postMeta = { components: [], steps: {} };

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  for (const child of children) {
    if (child != null) node.append(child);
  }
  return node;
}

function chip(status) {
  return el("span", { class: `chip ${status}` }, chipText[status] || status);
}

function drawComponents(components) {
  $("components").replaceChildren(...components.map((c) => el("tr", {},
    el("td", {}, c.name),
    el("td", {}, chip(c.automatic)),
    el("td", {}, chip(c.status)),
    el("td", { class: "muted" }, c.detail || ""))));
}

async function api(method, path, body) {
  const options = { method, headers: {} };
  if (body !== undefined) {
    options.headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(body);
  }
  const response = await fetch(path, options);
  if (!response.ok) throw new Error((await response.text()) || response.statusText);
  return response.status === 204 ? null : response.json();
}

function showFormFields() {
  const kind = $("p-kind").value;
  document.querySelectorAll("#new-post [data-for]").forEach((field) => {
    field.hidden = !field.dataset.for.split(" ").includes(kind);
  });
}

function postCard(post) {
  const closed = Boolean(post.closed);
  const step = post.updates.length ? post.updates[post.updates.length - 1].step : "";
  const names = post.components.map((id) => (postMeta.components.find((c) => c.id === id) || { name: id }).name);
  const meta = [kindText[post.kind]];
  if (post.impact) meta.push(post.impact === "major" ? "major" : "minor");
  if (post.starts) meta.push(`${timeFormat.format(new Date(post.starts))} – ${timeFormat.format(new Date(post.ends))}`);
  if (names.length) meta.push(names.join(", "));

  const updates = el("ol", {}, ...post.updates.map((u) => el("li", {},
    el("b", {}, stepText[u.step] || u.step), ` · ${timeFormat.format(new Date(u.time))}`, u.message ? ` · ${u.message}` : "")));

  const card = el("div", { class: `post${closed ? " closed" : ""}` },
    el("div", { class: "post-head" }, el("b", {}, post.title), el("span", { class: "chip" }, stepText[step] || step)),
    el("div", { class: "meta" }, meta.join(" · ")),
    updates);

  if (!closed) {
    const select = el("select", { "aria-label": "Next step" },
      ...(postMeta.steps[post.kind] || []).filter((s) => s !== step).map((s) => el("option", { value: s }, stepText[s] || s)));
    const message = el("input", { placeholder: "Message (optional)", maxlength: "2000", "aria-label": "Message" });
    const button = el("button", { type: "submit" }, "Add update");
    card.append(el("form", {
      onsubmit: async (event) => {
        event.preventDefault();
        button.disabled = true;
        try {
          await api("POST", `posts/${post.id}/updates`, { step: select.value, message: message.value });
          await loadPosts();
          refresh();
        } catch (error) {
          button.disabled = false;
          button.textContent = "Didn't work, try again";
        }
      },
    }, select, message, button));
  }

  let confirming = false;
  const remove = el("button", {
    type: "button", class: "danger",
    onclick: async () => {
      if (!confirming) {
        confirming = true;
        remove.textContent = "Click again to delete";
        setTimeout(() => { confirming = false; remove.textContent = "Delete"; }, 4000);
        return;
      }
      remove.disabled = true;
      await api("DELETE", `posts/${post.id}`).catch(() => {});
      await loadPosts();
      refresh();
    },
  }, "Delete");
  card.append(el("div", { class: "actions" }, remove));
  return card;
}

async function loadPosts() {
  try {
    const data = await api("GET", "posts");
    postMeta = { components: data.components, steps: data.steps };
    const boxes = $("p-components");
    if (!boxes.childElementCount) {
      boxes.replaceChildren(...data.components.map((c) => el("label", {},
        el("input", { type: "checkbox", value: c.id }), c.name)));
    }
    const list = $("posts");
    list.replaceChildren(...(data.posts.length ? data.posts.map(postCard) : [el("p", { class: "muted" }, "No posts yet. The public page shows only the automatic checks.")]));
  } catch (error) {
    $("posts").replaceChildren(el("p", { class: "muted" }, `Couldn't load posts: ${error.message}`));
  }
}

$("p-kind").addEventListener("change", showFormFields);
$("new-post").addEventListener("submit", async (event) => {
  event.preventDefault();
  const kind = $("p-kind").value;
  const body = {
    kind,
    title: $("p-title").value,
    impact: $("p-impact").value,
    message: $("p-message").value,
    components: [...document.querySelectorAll("#p-components input:checked")].map((box) => box.value),
  };
  if (kind === "maintenance") {
    if (!$("p-starts").value || !$("p-ends").value) {
      setText("p-result", "Maintenance needs a start and an end.");
      return;
    }
    body.starts = new Date($("p-starts").value).toISOString();
    body.ends = new Date($("p-ends").value).toISOString();
  }
  try {
    await api("POST", "posts", body);
    event.target.reset();
    showFormFields();
    setText("p-result", "Published.");
    await loadPosts();
    refresh();
  } catch (error) {
    setText("p-result", "That didn't work. Check the title and, for maintenance, that it ends after it starts.");
  }
});
showFormFields();
loadPosts();

refresh();
setInterval(refresh, 30000);
setInterval(tick, 5000);
window.addEventListener("resize", () => {
  if (lastHourly) drawChart(lastHourly);
});
