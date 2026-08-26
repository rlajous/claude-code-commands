#!/usr/bin/env node
// git-workflow — status-report.mjs
//
// Gathers current git/gh workflow state and injects it as JSON into
// ../assets/status-template.html, printing the resulting self-contained
// HTML page to stdout.
//
// Usage:
//   node skills/status/scripts/status-report.mjs > .git-workflow/status.html
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

function getDevelopmentBranch(warnings) {
  const canonical = path.join(process.cwd(), ".git-workflow", "config.yaml");
  const legacy = path.join(process.cwd(), ".claude", "config.yaml");
  const configPath = existsSync(canonical) ? canonical : existsSync(legacy) ? legacy : null;
  if (!configPath) return "staging";
  try {
    const raw = readFileSync(configPath, "utf8");
    const match = raw.match(/^\s*developmentBranch:\s*(.*?)\s*$/m);
    let value = null;
    if (match) {
      const scalar = match[1].replace(/\s+#.*$/, "").trim();
      const quoted = scalar.match(/^(["'])(.*)\1$/);
      if (quoted) value = quoted[2];
      else if (scalar && !/^[\[{|>]/.test(scalar) && !/^["']/.test(scalar)) value = scalar;
    }
    if (!value && /developmentBranch\s*:/.test(raw)) {
      warnings.push(`Could not parse developmentBranch from ${path.relative(process.cwd(), configPath)}; using staging.`);
    }
    return value || "staging";
  } catch (error) {
    warnings.push(`Could not read ${path.relative(process.cwd(), configPath)}: ${error.message}; using staging.`);
    return "staging";
  }
}

function getPrContext(warnings, currentBranch) {
  const canonical = path.join(process.cwd(), ".git-workflow", "pr-context.json");
  const legacy = path.join(process.cwd(), ".claude", ".pr-context.json");
  const contextPath = existsSync(canonical) ? canonical : existsSync(legacy) ? legacy : null;
  if (!contextPath) return null;
  try {
    const raw = readFileSync(contextPath, "utf8");
    const context = JSON.parse(raw);
    if (!context || typeof context !== "object" || Array.isArray(context)) {
      throw new TypeError("expected a JSON object");
    }
    if (context.branch && currentBranch && context.branch !== currentBranch) {
      warnings.push(`Ignored stale ${path.relative(process.cwd(), contextPath)} for branch ${context.branch}; current branch is ${currentBranch}.`);
      return null;
    }
    return context;
  } catch (error) {
    warnings.push(`Could not read ${path.relative(process.cwd(), contextPath)}: ${error.message}; ignoring PR context.`);
    return null;
  }
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
  const warnings = [];
  const branch = safe(() => run("git", ["rev-parse", "--abbrev-ref", "HEAD"]));
  const porcelain = safe(() => run("git", ["status", "--porcelain"]));
  const dirty = porcelain === null ? null : porcelain.length > 0;
  const developmentBranch = getDevelopmentBranch(warnings);
  const commitsAhead = branch ? getCommitsAhead(developmentBranch) : null;
  const pr = getPrInfo();
  const latestRelease = getLatestRelease();
  const prContext = getPrContext(warnings, branch);

  return {
    generatedAt: new Date().toISOString(),
    warnings,
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
