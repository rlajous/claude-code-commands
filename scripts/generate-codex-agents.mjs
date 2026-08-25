#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourceDir = path.join(root, "agents");
const outputDir = path.join(root, ".codex", "agents");
const checkOnly = process.argv.includes("--check");

const workspaceWriteAgents = new Set(["qa-executor", "release-validator"]);

function parseAgent(filePath) {
  const source = fs.readFileSync(filePath, "utf8");
  const match = source.match(/^---\n([\s\S]*?)\n---\n+([\s\S]*)$/);
  if (!match) throw new Error(`${filePath}: invalid YAML frontmatter`);

  const metadata = {};
  for (const line of match[1].split("\n")) {
    const field = line.match(/^([a-z-]+):\s*(.*)$/);
    if (field) metadata[field[1]] = field[2];
  }
  if (!metadata.name || !metadata.description) {
    throw new Error(`${filePath}: name and description are required`);
  }

  return {
    name: metadata.name,
    description: metadata.description,
    instructions: match[2].trimEnd(),
  };
}

function render(agent) {
  const sandbox = workspaceWriteAgents.has(agent.name) ? "workspace-write" : "read-only";
  return [
    "# Generated from agents/*.md by scripts/generate-codex-agents.mjs.",
    "# Edit the canonical Markdown agent and regenerate instead of editing this file.",
    `name = ${JSON.stringify(agent.name)}`,
    `description = ${JSON.stringify(agent.description)}`,
    `sandbox_mode = ${JSON.stringify(sandbox)}`,
    `developer_instructions = ${JSON.stringify(agent.instructions)}`,
    "",
  ].join("\n");
}

const files = fs.readdirSync(sourceDir).filter((name) => name.endsWith(".md")).sort();
const expected = new Set();
let failed = false;

if (!checkOnly) fs.mkdirSync(outputDir, { recursive: true });

for (const filename of files) {
  const agent = parseAgent(path.join(sourceDir, filename));
  const outputName = `${agent.name}.toml`;
  const outputPath = path.join(outputDir, outputName);
  const content = render(agent);
  expected.add(outputName);

  if (checkOnly) {
    if (!fs.existsSync(outputPath) || fs.readFileSync(outputPath, "utf8") !== content) {
      console.error(`OUTDATED: .codex/agents/${outputName}`);
      failed = true;
    }
  } else {
    fs.writeFileSync(outputPath, content);
    console.log(`generated .codex/agents/${outputName}`);
  }
}

if (fs.existsSync(outputDir)) {
  for (const filename of fs.readdirSync(outputDir).filter((name) => name.endsWith(".toml"))) {
    if (expected.has(filename)) continue;
    if (checkOnly) {
      console.error(`ORPHAN: .codex/agents/${filename}`);
      failed = true;
    } else {
      fs.unlinkSync(path.join(outputDir, filename));
      console.log(`removed .codex/agents/${filename}`);
    }
  }
}

if (failed) {
  console.error("Run: node scripts/generate-codex-agents.mjs");
  process.exit(1);
}
