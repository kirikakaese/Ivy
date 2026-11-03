// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
"use strict";

const $ = (id) => document.getElementById(id);

// Page texts in English and German. Posts carry their own German text when
// it was written; otherwise the English one shows.
const texts = {
  en: {
    tagline: "Ivy's services and the ones it depends on",
    checking: "Checking…", allGood: "All good", maintenance: "Maintenance", degraded: "Some trouble",
    downHeadline: "Something isn't working", error: "Status unavailable",
    ok: "Working", down: "Down", unknown: "Unknown", partial: "Part of the day", noData: "No data",
    marked: "Incident or maintenance",
    msg_ok: "Everything is working.",
    msg_maintenance: "Maintenance is under way. Notifications may be late meanwhile.",
    msg_degraded: "Some parts are slow or partly unavailable. Notifications may be late.",
    msg_down: "Part of Ivy isn't working right now. Ivy still gets messages while it's open.",
    msg_unknown: "The first check hasn't finished yet.",
    msg_error: "The status service didn't answer. If this lasts, Ivy Push may be down.",
    services: "Services", measurements: "Measurements",
    uptime30: "Uptime, 30 days", uptime90: "Uptime, 90 days", wake: "Wake-up time", wakeHint: "median, last 24 h",
    accepted: "Accepted by Apple", last24: "last 24 h", notEnough: "Not enough data yet",
    last90: "Last 90 days", daysLabel: "Status of each of the last 90 days", daysAgo: "90 days ago", today: "Today",
    past14: "Past 14 days",
    daysWithout: (p) => `${p} % of days without trouble`,
    serviceDays: (name) => `${name}, status of each of the last 90 days`,
    last90Up: (p) => `Last 90 days · ${p} % up`, last90None: "Last 90 days · no data yet",
    downWeek: "down this week", troubleWeek: "trouble this week",
    now: (detail) => `Now: ${detail}.`,
    workingAllDay: "Working all day", minDown: (d) => `${d} down`, minTrouble: (d) => `${d} some trouble`,
    minMaint: (d) => `${d} maintenance`, percentUp: (p) => `${p} % up`, yourTime: (z) => `Your time (${z})`,
    justNow: "just now", minAgo: (n) => `${n} min ago`, hAgo: (n) => `${n} h ago`,
    checked: (a) => `Checked ${a}. The page updates by itself.`,
    theme: "Appearance", themeAuto: "Automatic", themeLight: "Light", themeDark: "Dark",
    incident: "Incident", notice: "Notice",
    investigating: "Investigating", identified: "Identified", monitoring: "Monitoring", resolved: "Resolved",
    scheduled: "Scheduled", in_progress: "In progress", completed: "Completed", posted: "Posted", removed: "Removed",
    aboutRelay: "<b>Ivy Push relay</b> wakes Ivy on iPhone and iPad when a message arrives, so notifications come right away. It never sees what messages say or who sent them. When it's down, Ivy still gets messages while it's open and through Background App Refresh.",
    aboutWake: "<b>Wake-up time</b> is how long Apple takes to accept a wake-up from the relay; Apple's delivery to the phone comes after that. <b>Signal service</b> is checked from the relay: whether Signal's server answers and how fast. For Signal's own reports, see <a href=\"https://status.signal.org\" rel=\"noopener\">status.signal.org</a>.",
    services_relay: ["Ivy Push relay", "Stays connected to Signal for each account and notices new messages."],
    services_apple: ["Apple push delivery", "Hands wake-ups to Apple, which delivers them to iPhones and iPads."],
    services_signal: ["Signal service", "Signal's servers, which carry all of Ivy's messages and calls. Checked from the relay."],
    signalDetail: (detail) => detail,
  },
  de: {
    tagline: "Ivys Dienste und die, auf die Ivy angewiesen ist",
    checking: "Wird geprüft …", allGood: "Alles in Ordnung", maintenance: "Wartung", degraded: "Einige Probleme",
    downHeadline: "Etwas funktioniert nicht", error: "Status nicht verfügbar",
    ok: "Funktioniert", down: "Ausgefallen", unknown: "Unbekannt", partial: "Teil des Tages", noData: "Keine Daten",
    marked: "Störung oder Wartung",
    msg_ok: "Alles funktioniert.",
    msg_maintenance: "Es laufen Wartungsarbeiten. Mitteilungen können sich solange verspäten.",
    msg_degraded: "Einige Teile sind langsam oder teilweise nicht erreichbar. Mitteilungen können sich verspäten.",
    msg_down: "Ein Teil von Ivy funktioniert gerade nicht. Solange Ivy geöffnet ist, kommen Nachrichten weiter an.",
    msg_unknown: "Die erste Prüfung ist noch nicht fertig.",
    msg_error: "Der Statusdienst hat nicht geantwortet. Hält das an, ist Ivy Push vielleicht ausgefallen.",
    services: "Dienste", measurements: "Messwerte",
    uptime30: "Uptime, 30 Tage", uptime90: "Uptime, 90 Tage", wake: "Weckzeit", wakeHint: "Median, letzte 24 Std.",
    accepted: "Apple-Annahme", last24: "letzte 24 Std.", notEnough: "Noch nicht genug Daten",
    last90: "Letzte 90 Tage", daysLabel: "Status jedes der letzten 90 Tage", daysAgo: "Vor 90 Tagen", today: "Heute",
    past14: "Letzte 14 Tage",
    daysWithout: (p) => `${p} % der Tage ohne Probleme`,
    serviceDays: (name) => `${name}, Status jedes der letzten 90 Tage`,
    last90Up: (p) => `Letzte 90 Tage · ${p} % verfügbar`, last90None: "Letzte 90 Tage · noch keine Daten",
    downWeek: "diese Woche ausgefallen", troubleWeek: "diese Woche Probleme",
    now: (detail) => `Jetzt: ${detail}.`,
    workingAllDay: "Den ganzen Tag in Betrieb", minDown: (d) => `${d} ausgefallen`, minTrouble: (d) => `${d} Probleme`,
    minMaint: (d) => `${d} Wartung`, percentUp: (p) => `${p} % verfügbar`, yourTime: (z) => `Deine Zeit (${z})`,
    justNow: "gerade eben", minAgo: (n) => `vor ${n} Min.`, hAgo: (n) => `vor ${n} Std.`,
    checked: (a) => `Geprüft ${a}. Die Seite aktualisiert sich selbst.`,
    theme: "Darstellung", themeAuto: "Automatisch", themeLight: "Hell", themeDark: "Dunkel",
    incident: "Störung", notice: "Hinweis",
    investigating: "Wird untersucht", identified: "Ursache gefunden", monitoring: "Wird beobachtet", resolved: "Behoben",
    scheduled: "Geplant", in_progress: "Läuft", completed: "Abgeschlossen", posted: "Veröffentlicht", removed: "Entfernt",
    aboutRelay: "<b>Ivy Push Relay</b> weckt Ivy auf iPhone und iPad, wenn eine Nachricht ankommt, damit Mitteilungen sofort erscheinen. Es sieht nie, was in Nachrichten steht oder wer sie geschickt hat. Ist es ausgefallen, bekommt Ivy Nachrichten weiterhin, solange es geöffnet ist, und über die Hintergrundaktualisierung.",
    aboutWake: "<b>Weckzeit</b> ist, wie lange Apple braucht, um ein Wecksignal vom Relay anzunehmen; die Zustellung ans Telefon folgt danach. <b>Signal-Dienst</b> wird vom Relay aus geprüft: ob Signals Server antwortet und wie schnell. Signals eigene Meldungen stehen auf <a href=\"https://status.signal.org\" rel=\"noopener\">status.signal.org</a>.",
    services_relay: ["Ivy Push Relay", "Bleibt für jedes Konto mit Signal verbunden und bemerkt neue Nachrichten."],
    services_apple: ["Apple-Push-Zustellung", "Gibt Wecksignale an Apple weiter, das sie an iPhones und iPads zustellt."],
    services_signal: ["Signal-Dienst", "Signals Server, über die alle Nachrichten und Anrufe von Ivy laufen. Vom Relay aus geprüft."],
    signalDetail: (detail) => detail
      .replace(/^reachable, (\d+) ms$/, "erreichbar, $1 ms")
      .replace(/^slow, ([\d.]+) s$/, (_, s) => `langsam, ${s.replace(".", ",")} s`)
      .replace(/^answering with errors \((\d+)\)$/, "antwortet mit Fehlern ($1)")
      .replace(/^not answering$/, "antwortet nicht"),
  },
};
const headlineKey = { ok: "allGood", maintenance: "maintenance", degraded: "degraded", down: "downHeadline", unknown: "checking", error: "error" };
const chipKey = { ok: "ok", maintenance: "maintenance", degraded: "degraded", down: "down", unknown: "unknown" };
const dayColor = { ok: "var(--ok)", maintenance: "var(--maint)", degraded: "var(--warn)", down: "var(--bad)", none: "var(--none)" };

function stored(key) {
  try { return localStorage.getItem(key); } catch { return null; }
}
function store(key, value) {
  try { localStorage.setItem(key, value); } catch {}
}

let lang = stored("ivy-status-lang") || ((navigator.languages || [navigator.language]).find((l) => /^(de|en)\b/i.test(l)) || "en").slice(0, 2).toLowerCase();
if (lang !== "de") lang = "en";
const t = (key, ...args) => {
  const value = texts[lang][key] ?? texts.en[key];
  return typeof value === "function" ? value(...args) : value ?? key;
};
const stepLabel = (step) => (texts.en[step] ? t(step) : step);
const kindLabel = (kind) => t(kind);
// Posts name their services in English; this shows them in the page's language.
const serviceName = (name) => {
  const id = ["relay", "apple", "signal"].find((key) => texts.en[`services_${key}`][0] === name);
  return id ? t(`services_${id}`)[0] : name;
};
const postTitle = (post) => (lang === "de" && post.titleDe) || post.title;
const updateMessage = (update) => (lang === "de" && update.messageDe) || update.message;

let dateFormat, timeFormat, percent, hourFormat;
function setFormats() {
  const locale = lang === "de" ? "de-DE" : undefined;
  dateFormat = new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeZone: "UTC" });
  timeFormat = new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeStyle: "short" });
  percent = new Intl.NumberFormat(locale, { maximumFractionDigits: 2 });
  hourFormat = new Intl.DateTimeFormat(locale, { hour: "numeric" });
}
setFormats();
let checked = null;
let lastData = null;
let failed = false;
// Services whose 90 days are open, kept across refreshes.
const openServices = new Set();
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
  if (seconds < 60) return t("justNow");
  if (seconds < 3600) return t("minAgo", Math.floor(seconds / 60));
  return t("hAgo", Math.floor(seconds / 3600));
}

function renderPost(post) {
  const classes = ["post", post.kind, post.impact || ""].join(" ");
  const meta = [kindLabel(post.kind)];
  if (post.kind === "maintenance" && post.starts) {
    meta.push(`${timeFormat.format(new Date(post.starts))} – ${timeFormat.format(new Date(post.ends))}`);
  }
  if (post.components && post.components.length) meta.push(post.components.map(serviceName).join(", "));
  const updates = el("ol");
  for (const update of [...post.updates].reverse()) {
    updates.append(el("li", {},
      el("b", {}, stepLabel(update.step)),
      el("time", { datetime: update.time }, timeFormat.format(new Date(update.time))),
      updateMessage(update) ? el("div", {}, updateMessage(update)) : null));
  }
  return el("article", { class: classes },
    el("h3", {}, postTitle(post)),
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
  if (!m) return t("noData");
  const parts = [];
  if (m.down) parts.push(t("minDown", duration(m.down)));
  if (m.degraded) parts.push(t("minTrouble", duration(m.degraded)));
  if (m.maintenance) parts.push(t("minMaint", duration(m.maintenance)));
  const total = m.ok + m.maintenance + m.degraded + m.down;
  if (!parts.length) return t("workingAllDay");
  parts.push(t("percentUp", percent.format(((total - m.down) / total) * 100)));
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
    const titles = posts.map((post) => `${kindLabel(post.kind)}: ${postTitle(post)}`);
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
  const part = new Intl.DateTimeFormat(lang === "de" ? "de-DE" : undefined, { timeZoneName: "short" }).formatToParts(new Date(date + "T12:00:00Z")).find((p) => p.type === "timeZoneName");
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
    el("span", { class: "zone" }, t("yourTime", zoneName(day.date))),
    ...span.ivyPosts.map((post) => el("span", { class: `post-line ${markClass(post)}` }, `${kindLabel(post.kind)}: ${postTitle(post)}`)));
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

// With a mouse the tooltip follows the pointer; a tap shows it until the
// next tap elsewhere. Phones don't send clicks for plain page areas, so
// taps are taken from pointerdown.
document.addEventListener("pointerover", (event) => {
  if (event.target.ivyDay) showTip(event.target);
});
document.addEventListener("pointerout", (event) => {
  if (event.pointerType !== "touch" && event.target.ivyDay && !(event.relatedTarget && event.relatedTarget.ivyDay)) hideTip();
});
document.addEventListener("pointerdown", (event) => {
  if (event.target.ivyDay) showTip(event.target);
  else hideTip();
});
window.addEventListener("scroll", hideTip, { passive: true });
window.addEventListener("blur", hideTip);

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
  if (week.includes("down")) return { class: "down", text: t("downWeek") };
  if (week.includes("degraded")) return { class: "degraded", text: t("troubleWeek") };
  return null;
}

function renderService(c) {
  const [name, description] = texts.en[`services_${c.id}`] ? t(`services_${c.id}`) : [c.name, c.description];
  const days = el("div", { class: "days", role: "group", "aria-label": t("serviceDays", name) });
  const marks = el("div", { class: "marks", "aria-hidden": "true" });
  renderDays(days, marks, c.days || [], name, c.name);
  const up = uptime(c.days || []);
  const week = lastWeek(c.days || []);
  const summary = el("summary", {}, up == null ? t("last90None") : t("last90Up", percent.format(up)));
  if (week) summary.append(el("span", { class: `week ${week.class}` }, week.text));
  const details = el("details", { class: "service-days" },
    summary,
    days,
    marks,
    el("div", { class: "scale muted" }, el("span", {}, t("daysAgo")), el("span", {}, t("today"))));
  details.open = openServices.has(c.id);
  details.addEventListener("toggle", () => {
    if (details.open) openServices.add(c.id);
    else openServices.delete(c.id);
  });
  return el("li", {},
    el("span", { class: "name" }, name),
    el("span", { class: `chip ${c.status}` }, chipKey[c.status] ? t(chipKey[c.status]) : c.status),
    el("span", { class: "desc" }, c.detail ? `${description} ${t("now", t("signalDetail", c.detail))}` : description),
    details);
}

function renderPosts(container, posts) {
  container.replaceChildren(...posts.map(renderPost));
  container.hidden = posts.length === 0;
}

function metric(id, value, format) {
  $(id).textContent = value == null ? "–" : format(value);
  $(id).title = value == null ? t("notEnough") : "";
}

function headline(status) {
  return headlineKey[status] ? t(headlineKey[status]) : status;
}

function render(data) {
  lastData = data;
  failed = false;
  checked = data.checked;
  marked = data.marked || [];
  $("hero").dataset.status = data.status;
  $("headline").textContent = headline(data.status);
  $("message").textContent = texts.en[`msg_${data.status}`] ? t(`msg_${data.status}`) : data.message;
  document.title = `${headline(data.status)} · Ivy Status`;

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
  $("uptime-days").textContent = known ? t("daysWithout", percent.format((good / known) * 100)) : "";
  tick();
}

function tick() {
  $("checked").textContent = checked ? t("checked", ago(checked)) : "";
}

async function refresh() {
  try {
    const response = await fetch("status.json", { cache: "no-store" });
    if (!response.ok) throw new Error(response.statusText);
    render(await response.json());
  } catch {
    failed = true;
    showError();
  }
}

function showError() {
  $("hero").dataset.status = "error";
  $("headline").textContent = t("error");
  $("message").textContent = t("msg_error");
}

// The fixed texts of the page, in the chosen language.
function applyLanguage() {
  document.documentElement.lang = lang;
  setFormats();
  document.querySelectorAll("[data-t]").forEach((node) => { node.textContent = t(node.dataset.t); });
  // Only the page's own texts above, never anything from the server.
  document.querySelectorAll("[data-t-html]").forEach((node) => { node.innerHTML = t(node.dataset.tHtml); });
  document.querySelectorAll("[data-t-label]").forEach((node) => node.setAttribute("aria-label", t(node.dataset.tLabel)));
  document.querySelectorAll("[data-t-title]").forEach((node) => { node.title = t(node.dataset.tTitle); node.setAttribute("aria-label", t(node.dataset.tTitle)); });
  markSelected($("lang"), lang);
  if (lastData) render(lastData);
  if (failed) showError();
}

function markSelected(group, value) {
  group.querySelectorAll("button").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.value === value)));
}

function currentTheme() {
  const theme = document.documentElement.dataset.theme;
  return theme === "light" || theme === "dark" ? theme : "auto";
}

$("lang").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-value]");
  if (!button || button.dataset.value === lang) return;
  lang = button.dataset.value;
  store("ivy-status-lang", lang);
  hideTip();
  applyLanguage();
});

$("theme").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-value]");
  if (!button) return;
  const theme = button.dataset.value;
  if (theme === "auto") delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = theme;
  store("ivy-status-theme", theme);
  markSelected($("theme"), theme);
});

markSelected($("theme"), currentTheme());
applyLanguage();

refresh();
setInterval(refresh, 60000);
setInterval(tick, 10000);
