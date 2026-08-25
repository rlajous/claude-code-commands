#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
const options = {
  target: process.cwd(),
  source: process.env.PLUGIN_ROOT || process.env.CLAUDE_PLUGIN_ROOT || "",
  host: "codex",
  dryRun: false,
  force: false,
  prune: false,
  confirmPrune: false,
  migrateConfig: false,
  initializeConfig: false,
};

for (let index = 0; index < args.length; index += 1) {
  const arg = args[index];
  if (arg === "--target" || arg === "--source" || arg === "--host") {
    const value = args[index + 1];
    if (!value) throw new Error(`${arg} requires a value`);
    options[arg.slice(2)] = value;
    index += 1;
  } else if (arg === "--dry-run") options.dryRun = true;
  else if (arg === "--force") options.force = true;
  else if (arg === "--prune") options.prune = true;
  else if (arg === "--confirm-prune") options.confirmPrune = true;
  else if (arg === "--migrate-config") options.migrateConfig = true;
  else if (arg === "--initialize-config") options.initializeConfig = true;
  else throw new Error(`unknown option: ${arg}`);
}

if (!options.source) throw new Error("source is required (--source, PLUGIN_ROOT, or CLAUDE_PLUGIN_ROOT)");
if (!["codex", "claude", "both"].includes(options.host)) throw new Error("--host must be codex, claude, or both");

const sourceRoot = path.resolve(options.source);
const targetRoot = path.resolve(options.target);
const ledgerPath = path.join(targetRoot, ".git-workflow", "version.json");
const manifestPath = path.join(sourceRoot, ".codex-plugin", "plugin.json");

for (const required of ["skills", "agents", path.join(".codex", "agents")]) {
  if (!fs.existsSync(path.join(sourceRoot, required))) throw new Error(`incomplete source: missing ${required}`);
}

const version = fs.existsSync(manifestPath)
  ? JSON.parse(fs.readFileSync(manifestPath, "utf8")).version
  : "unknown";

function listFiles(root, suffix) {
  if (!fs.existsSync(root)) return [];
  const result = [];
  const visit = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(absolute);
      else if (!suffix || entry.name.endsWith(suffix)) result.push(absolute);
    }
  };
  visit(root);
  return result.sort();
}

const mappings = [];
function mapTree(sourceDirectory, targetDirectory, suffix) {
  for (const source of listFiles(sourceDirectory, suffix)) {
    const relative = path.relative(sourceDirectory, source);
    mappings.push({ source, target: path.join(targetDirectory, relative) });
  }
}

if (options.host === "codex" || options.host === "both") {
  mapTree(path.join(sourceRoot, ".codex", "agents"), path.join(targetRoot, ".codex", "agents"), ".toml");
}
if (options.host === "claude" || options.host === "both") {
  mapTree(path.join(sourceRoot, "skills"), path.join(targetRoot, ".claude", "skills"), null);
  mapTree(path.join(sourceRoot, "agents"), path.join(targetRoot, ".claude", "agents"), ".md");
  mapTree(path.join(sourceRoot, "references"), path.join(targetRoot, ".claude", "references"), ".md");
}

const report = { installed: [], updated: [], unchanged: [], preserved: [], pruned: [], migrated: [] };
const relativeTarget = (file) => path.relative(targetRoot, file).split(path.sep).join("/");

function sameFile(left, right) {
  return fs.existsSync(left) && fs.existsSync(right) && fs.readFileSync(left).equals(fs.readFileSync(right));
}

function showDiff(source, target) {
  const result = spawnSync("diff", ["-u", target, source], { encoding: "utf8" });
  if (result.stdout) process.stdout.write(result.stdout);
}

function atomicCopy(source, target) {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = path.join(path.dirname(target), `.${path.basename(target)}.${process.pid}.${Date.now()}`);
  fs.copyFileSync(source, temporary);
  fs.renameSync(temporary, target);
}

for (const mapping of mappings) {
  const relative = relativeTarget(mapping.target);
  if (!fs.existsSync(mapping.target)) {
    report.installed.push(relative);
    if (!options.dryRun) atomicCopy(mapping.source, mapping.target);
  } else if (sameFile(mapping.source, mapping.target)) {
    report.unchanged.push(relative);
  } else {
    showDiff(mapping.source, mapping.target);
    if (options.force) {
      report.updated.push(relative);
      if (!options.dryRun) atomicCopy(mapping.source, mapping.target);
    } else {
      report.preserved.push(relative);
    }
  }
}

let priorLedger = {};
if (fs.existsSync(ledgerPath)) {
  try {
    priorLedger = JSON.parse(fs.readFileSync(ledgerPath, "utf8"));
  } catch (error) {
    throw new Error(`invalid version ledger ${ledgerPath}: ${error.message}`);
  }
}

if (options.prune) {
  const expected = new Set(mappings.map(({ target }) => relativeTarget(target)));
  const candidates = (priorLedger.managed_files || []).filter((relative) => !expected.has(relative));
  if (candidates.length && !options.confirmPrune) {
    for (const relative of candidates) console.log(`? ${relative}`);
    throw new Error("prune candidates require --confirm-prune after review");
  }
  for (const relative of candidates) {
    const candidate = path.resolve(targetRoot, relative);
    if (candidate !== targetRoot && candidate.startsWith(`${targetRoot}${path.sep}`) && fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
      report.pruned.push(relative);
      if (!options.dryRun) fs.unlinkSync(candidate);
    }
  }
}

if (options.migrateConfig || options.initializeConfig) {
  const canonical = path.join(targetRoot, ".git-workflow", "config.yaml");
  const legacy = path.join(targetRoot, ".claude", "config.yaml");
  const template = path.join(sourceRoot, "templates", "config.yaml.template");
  if (options.migrateConfig && !fs.existsSync(canonical) && fs.existsSync(legacy)) {
    report.migrated.push(".claude/config.yaml -> .git-workflow/config.yaml");
    if (!options.dryRun) atomicCopy(legacy, canonical);
  } else if (options.initializeConfig && !fs.existsSync(canonical) && !fs.existsSync(legacy)) {
    report.installed.push(".git-workflow/config.yaml");
    if (!options.dryRun) atomicCopy(template, canonical);
  } else if (fs.existsSync(canonical) && fs.existsSync(legacy) && !sameFile(canonical, legacy)) {
    showDiff(legacy, canonical);
    report.preserved.push(".git-workflow/config.yaml (differs from legacy fallback)");
  }
}

const managedFiles = mappings.map(({ target }) => relativeTarget(target));
if (!options.dryRun) {
  fs.mkdirSync(path.dirname(ledgerPath), { recursive: true });
  const ledger = {
    version,
    source: sourceRoot,
    installed_at: new Date().toISOString(),
    hosts: options.host === "both" ? ["claude", "codex"] : [options.host],
    managed_files: managedFiles,
  };
  const temporary = path.join(path.dirname(ledgerPath), `.version.json.${process.pid}.${Date.now()}`);
  fs.writeFileSync(temporary, `${JSON.stringify(ledger, null, 2)}${os.EOL}`);
  fs.renameSync(temporary, ledgerPath);
}

for (const [group, files] of Object.entries(report)) {
  for (const file of files) console.log(`${group}: ${file}`);
}

if (report.preserved.length) {
  console.error("Customized files were preserved. Review the diff and rerun with --force to replace them.");
  process.exitCode = 3;
}
