#!/usr/bin/env node
// Check relative Markdown links in the project knowledge layer.
import { readFileSync, readdirSync, statSync, lstatSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

const root = resolve(dirname(new URL(import.meta.url).pathname), "../..");
const roots = [
  "README.md",
  "CONTRIBUTING.md",
  "AGENTS.md",
  ".ai",
  ".agents",
  ".github",
  "specs",
  "decisions",
  "rfcs",
  "runbook",
  "tools",
  "data/sql/custom",
];

const required = [
  "README.md",
  "CONTRIBUTING.md",
  "AGENTS.md",
  ".ai/README.md",
  "specs/README.md",
  "decisions/README.md",
  "runbook/README.md",
];

const files = [];
const walk = (path) => {
  const full = join(root, path);
  if (!existsSync(full)) return;
  if (lstatSync(full).isSymbolicLink()) return;
  const stat = statSync(full);
  if (stat.isDirectory()) {
    for (const entry of readdirSync(full)) walk(join(path, entry));
  } else if (path.endsWith(".md")) {
    files.push(path);
  }
};
for (const path of roots) walk(path);

const errors = [];
for (const file of required) {
  if (!existsSync(join(root, file))) errors.push(`${file}: required file missing`);
}

const linkPattern = /(!?)\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
for (const file of files) {
  let text = readFileSync(join(root, file), "utf8");
  text = text.replace(/^```[\s\S]*?^```/gm, "");
  for (const match of text.matchAll(linkPattern)) {
    let target = match[2];
    if (!target || target.startsWith("#")) continue;
    if (/^(https?:|mailto:|tel:)/i.test(target)) continue;
    target = target.split("#")[0];
    if (!target) continue;
    const resolved = resolve(dirname(join(root, file)), target);
    if (!existsSync(resolved)) {
      errors.push(`${file}: broken link -> ${match[2]}`);
    }
  }
}

if (errors.length > 0) {
  console.error(`docs check: ${errors.length} problem(s)`);
  for (const error of errors) console.error(`  ${error}`);
  process.exit(1);
}

console.log(`docs check: ok (${files.length} files)`);
