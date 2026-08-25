#!/usr/bin/env node
// git-workflow — status-report.mjs
//
// Gathers current git/gh workflow state and injects it as JSON into
// assets/status-template.html, printing the resulting self-contained
// HTML page to stdout.
//
// Usage:
//   node scripts/status-report.mjs > .git-workflow/status.html
//
// Plain Node ESM, no dependencies (node:child_process, node:fs, node:path only).
// Never throws: every external command is wrapped in try/catch and failures
// degrade to `null` fields in the emitted JSON. Always exits 0.

import { execFileSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

function run(cmd, args) {
  return execFileSync(cmd, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
}

function safe(fn, fallback = null) {
  try {
    return fn();
  } catch {
    return fallback;
  }
}

function getDevelopmentBranch() {
  const configPath = firstExistingPath([
    path.join(process.cwd(), ".git-workflow", "config.yaml"),
    path.join(process.cwd(), ".claude", "config.yaml"),
  ]);
  if (!configPath) return "staging";
  try {
    const raw = readFileSync(configPath, "utf8");
    const match = raw.match(/developmentBranch:\s*["']?([\w./-]+)["']?/);
    return match ? match[1] : "staging";
  } catch {
    return "staging";
  }
}

function getPrContext() {
  const contextPath = firstExistingPath([
    path.join(process.cwd(), ".git-workflow", "pr-context.json"),
    path.join(process.cwd(), ".claude", ".pr-context.json"),
  ]);
  if (!contextPath) return null;
  try {
    const raw = readFileSync(contextPath, "utf8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function firstExistingPath(paths) {
  return paths.find((candidate) => existsSync(candidate)) ?? null;
}

function getCommitsAhead(devBranch) {
  // Try against origin/{devBranch} first, then fall back to the local branch.
  const attempts = [
    ["git", ["rev-list", "--count", `origin/${devBranch}..HEAD`]],
    ["git", ["rev-list", "--count", `${devBranch}..HEAD`]],
  ];
  for (const [cmd, args] of attempts) {
    const result = safe(() => run(cmd, args));
    if (result !== null && result !== "") {
      const n = Number.parseInt(result, 10);
      if (!Number.isNaN(n)) return n;
    }
  }
  return null;
}

function getPrInfo() {
  return safe(() => {
    const raw = run("gh", [
      "pr",
      "view",
      "--json",
      "number,title,state,reviewDecision,url",
    ]);
    return JSON.parse(raw);
  });
}

function getLatestRelease() {
  return safe(() => {
    const raw = run("gh", ["release", "list", "--limit", "1"]);
    if (!raw) return null;
    // `gh release list` prints tab-separated columns:
    // title \t type \t tagName \t publishedAt
    const [title, releaseType, tagName, publishedAt] = raw.split("\t");
    return {
      title: title ?? null,
      type: releaseType ?? null,
      tagName: tagName ?? null,
      publishedAt: publishedAt ?? null,
    };
  });
}

function buildState() {
  const branch = safe(() => run("git", ["rev-parse", "--abbrev-ref", "HEAD"]));
  const porcelain = safe(() => run("git", ["status", "--porcelain"]));
  const dirty = porcelain === null ? null : porcelain.length > 0;
  const developmentBranch = getDevelopmentBranch();
  const commitsAhead = branch ? getCommitsAhead(developmentBranch) : null;
  const pr = getPrInfo();
  const latestRelease = getLatestRelease();
  const prContext = getPrContext();

  return {
    generatedAt: new Date().toISOString(),
    branch,
    developmentBranch,
    dirty,
    commitsAhead,
    pr,
    latestRelease,
    ticket: prContext
      ? {
          id: prContext.ticket_id ?? null,
          title: prContext.ticket_title ?? null,
          url: prContext.ticket_url ?? null,
        }
      : null,
  };
}

function main() {
  const state = buildState();

  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const templatePath = path.join(scriptDir, "..", "assets", "status-template.html");

  let template;
  try {
    template = readFileSync(templatePath, "utf8");
  } catch (err) {
    // Fall back to a minimal inline page if the template is missing so the
    // command still produces something usable.
    template =
      "<!doctype html><html><body><pre id=\"status-data-fallback\">__STATUS_DATA__</pre></body></html>";
  }

  const html = template.replace("__STATUS_DATA__", JSON.stringify(state));
  process.stdout.write(html);
}

main();
process.exitCode = 0;
