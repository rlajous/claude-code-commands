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

const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:[-+][0-9A-Za-z.-]+)?$/;

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

const requestedSource = options.source;
let temporarySource = "";
if (/^(?:file|https?|ssh|git):\/\//.test(requestedSource) || /^[^/\s]+@[^:]+:.+/.test(requestedSource)) {
  temporarySource = fs.mkdtempSync(path.join(os.tmpdir(), "git-workflow-source-"));
  const clone = spawnSync("git", ["clone", "--depth", "1", requestedSource, temporarySource], {
    encoding: "utf8",
  });
  if (clone.error || clone.signal || clone.status !== 0) {
    fs.rmSync(temporarySource, { recursive: true, force: true });
    const detail = clone.error?.message || clone.stderr?.trim() || `exit ${clone.status ?? "unknown"}`;
    throw new Error(`failed to clone source ${requestedSource}: ${detail}`);
  }
  process.on("exit", () => fs.rmSync(temporarySource, { recursive: true, force: true }));
}

const sourceRoot = path.resolve(temporarySource || requestedSource);
const targetRoot = path.resolve(options.target);
const ledgerPath = path.join(targetRoot, ".git-workflow", "version.json");
const manifestPath = path.join(sourceRoot, ".codex-plugin", "plugin.json");

for (const required of ["skills", "agents", path.join(".codex", "agents"), path.join(".codex-plugin", "plugin.json")]) {
  if (!fs.existsSync(path.join(sourceRoot, required))) throw new Error(`incomplete source: missing ${required}`);
}

let manifest;
try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
} catch (error) {
  throw new Error(`invalid source manifest ${manifestPath}: ${error.message}`);
}
if (!manifest || typeof manifest !== "object" || Array.isArray(manifest) || typeof manifest.version !== "string" || !SEMVER.test(manifest.version)) {
  throw new Error(`invalid source manifest ${manifestPath}: version must be strict semver`);
}
const version = manifest.version;

function hostForManagedPath(relative) {
  if (relative.startsWith(".claude/")) return "claude";
  if (relative.startsWith(".codex/")) return "codex";
  return null;
}

function validateManagedPath(value) {
  if (typeof value !== "string" || !value || path.isAbsolute(value) || value.includes("\\")) return false;
  const segments = value.split("/");
  return !segments.some((segment) => !segment || segment === "." || segment === "..") && hostForManagedPath(value) !== null;
}

function readLedger() {
  if (!fs.existsSync(ledgerPath)) return {};
  let value;
  try {
    value = JSON.parse(fs.readFileSync(ledgerPath, "utf8"));
  } catch (error) {
    throw new Error(`invalid version ledger ${ledgerPath}: ${error.message}`);
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`invalid version ledger ${ledgerPath}: expected an object`);
  }
  for (const field of ["version", "source", "installed_at"]) {
    if (value[field] !== undefined && typeof value[field] !== "string") {
      throw new Error(`invalid version ledger ${ledgerPath}: ${field} must be a string`);
    }
  }
  if (value.hosts !== undefined && (!Array.isArray(value.hosts) || value.hosts.some((host) => !["claude", "codex"].includes(host)))) {
    throw new Error(`invalid version ledger ${ledgerPath}: hosts must contain only claude or codex`);
  }
  if (value.managed_files !== undefined && (!Array.isArray(value.managed_files) || value.managed_files.some((item) => !validateManagedPath(item)))) {
    throw new Error(`invalid version ledger ${ledgerPath}: managed_files must contain safe .claude/ or .codex/ relative paths`);
  }
  return {
    ...value,
    hosts: [...new Set(value.hosts || [])],
    managed_files: [...new Set(value.managed_files || [])],
  };
}

// Validate all externally controlled state before copying, pruning, or migrating anything.
const priorLedger = readLedger();

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
  if (result.error || result.signal || ![0, 1].includes(result.status)) {
    const detail = result.error?.message || result.stderr?.trim() || `exit ${result.status ?? "unknown"}`;
    throw new Error(`failed to preview diff for ${relativeTarget(target)}: ${detail}`);
  }
}

function atomicCopy(source, target) {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = path.join(path.dirname(target), `.${path.basename(target)}.${process.pid}.${Date.now()}`);
  fs.copyFileSync(source, temporary);
  fs.renameSync(temporary, target);
}

const priorManaged = new Set(priorLedger.managed_files || []);
const ownedSelected = new Set();
for (const mapping of mappings) {
  const relative = relativeTarget(mapping.target);
  if (!fs.existsSync(mapping.target)) {
    report.installed.push(relative);
    ownedSelected.add(relative);
    if (!options.dryRun) atomicCopy(mapping.source, mapping.target);
  } else if (sameFile(mapping.source, mapping.target)) {
    report.unchanged.push(relative);
    ownedSelected.add(relative);
  } else {
    showDiff(mapping.source, mapping.target);
    if (options.force) {
      report.updated.push(relative);
      ownedSelected.add(relative);
      if (!options.dryRun) atomicCopy(mapping.source, mapping.target);
    } else {
      report.preserved.push(relative);
      if (priorManaged.has(relative)) ownedSelected.add(relative);
    }
  }
}

const selectedHosts = new Set(options.host === "both" ? ["claude", "codex"] : [options.host]);
const expected = new Set(mappings.map(({ target }) => relativeTarget(target)));
const pruneCandidates = [...priorManaged].filter((relative) => {
  const owner = hostForManagedPath(relative);
  return owner && selectedHosts.has(owner) && !expected.has(relative);
});
const confirmedPruned = new Set();

if (options.prune) {
  if (pruneCandidates.length && !options.confirmPrune) {
    for (const relative of pruneCandidates) console.log(`? ${relative}`);
    throw new Error("prune candidates require --confirm-prune after review");
  }
  for (const relative of pruneCandidates) {
    confirmedPruned.add(relative);
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

const managedFiles = [...new Set([
  ...[...priorManaged].filter((relative) => !confirmedPruned.has(relative)),
  ...ownedSelected,
])].sort();
if (!options.dryRun) {
  fs.mkdirSync(path.dirname(ledgerPath), { recursive: true });
  const ledger = {
    version,
    source: requestedSource,
    installed_at: new Date().toISOString(),
    hosts: [...new Set([...(priorLedger.hosts || []), ...selectedHosts])].sort(),
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
