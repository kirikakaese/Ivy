// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
// Loaded first, so a chosen light or dark theme shows without a flash.
"use strict";
try {
  const theme = localStorage.getItem("ivy-status-theme");
  if (theme === "light" || theme === "dark") document.documentElement.dataset.theme = theme;
} catch {}
