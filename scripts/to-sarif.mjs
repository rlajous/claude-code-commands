#!/usr/bin/env node
// git-workflow — to-sarif.mjs
//
// Reads a JSON array of review findings from stdin and writes a SARIF 2.1.0
// log to stdout, for consumption by CI / code-scanning tools (e.g. GitHub
// code scanning `upload-sarif`).
//
// Input (stdin), each finding shaped like:
//   {
//     "file": "src/x.ts",
//     "line": 45,
//     "severity": "HIGH" | "MEDIUM" | "LOW" | "BLOCKING",
//     "confidence": 90,
//     "message": "...",
//     "rule": "optional-rule-id"
//   }
//
// Usage:
//   node scripts/to-sarif.mjs < findings.json > review.sarif
//   echo '[{"file":"a.ts","line":3,"severity":"HIGH","confidence":90,"message":"x"}]' \
//     | node scripts/to-sarif.mjs
//
// Plain Node ESM, no dependencies. Robust to missing/malformed fields.

const SARIF_SCHEMA =
  "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json";

function severityToLevel(severity) {
  const s = String(severity ?? "").toUpperCase();
  if (s === "BLOCKING" || s === "HIGH") return "error";
  if (s === "MEDIUM") return "warning";
  if (s === "LOW") return "note";
  // Unknown/missing severity: default to a safe, visible level.
  return "warning";
}

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", reject);
  });
}

function toResult(finding) {
  const file = finding?.file ?? "unknown";
  const line = Number.isInteger(finding?.line) && finding.line > 0 ? finding.line : 1;
  const message = finding?.message ?? "";
  const rule = finding?.rule ?? "review-finding";
  const confidence = finding?.confidence ?? null;

  return {
    ruleId: rule,
    level: severityToLevel(finding?.severity),
    message: {
      text: message,
    },
    locations: [
      {
        physicalLocation: {
          artifactLocation: {
            uri: file,
          },
          region: {
            startLine: line,
          },
        },
      },
    ],
    properties: {
      confidence,
    },
  };
}

async function main() {
  let raw;
  try {
    raw = await readStdin();
  } catch {
    raw = "";
  }

  let findings = [];
  if (raw && raw.trim().length > 0) {
    try {
      const parsed = JSON.parse(raw);
      findings = Array.isArray(parsed) ? parsed : [];
    } catch {
      findings = [];
    }
  }

  const results = findings
    .filter((f) => f && typeof f === "object")
    .map(toResult);

  const sarif = {
    version: "2.1.0",
    $schema: SARIF_SCHEMA,
    runs: [
      {
        tool: {
          driver: {
            name: "git-workflow-review",
            informationUri: "https://github.com/rlajous/claude-code-commands",
            rules: [],
          },
        },
        results,
      },
    ],
  };

  process.stdout.write(JSON.stringify(sarif, null, 2) + "\n");
}

main();
