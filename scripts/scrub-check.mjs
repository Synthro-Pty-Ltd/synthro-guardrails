#!/usr/bin/env node
// scrub-check — refuses a release that carries anything that must never leave.
//
// Two layers:
//   1. Built-in patterns for things that are never acceptable in a public repo:
//      keys, tokens, private keys, connection strings with a password, hosted
//      database hosts, real email addresses, and real-looking UUIDs (the fixtures
//      use synthetic ids that start 00000000-).
//   2. A LOCAL denylist, `.scrub-denylist`, that is gitignored and never
//      published. It holds the names that are private by nature — customers,
//      people, internal identifiers — so the list of secrets is not itself
//      published as the thing that protects them.
//
// It never prints what it matched. A finding names the file, the line, the
// column and the rule; the value stays where it is. Printing a secret to prove
// you found it is how secrets reach logs.
//
// Usage:
//   node scripts/scrub-check.mjs              scan the repo
//   node scripts/scrub-check.mjs --release    scan, and FAIL if the local denylist is missing
//   node scripts/scrub-check.mjs --self-test  prove every rule fires, and stays quiet on clean text

import { readFileSync, readdirSync, statSync, existsSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join, relative } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const SKIP_DIRS = new Set(['.git', 'node_modules']);
const SKIP_FILES = new Set(['.scrub-denylist']);

const RULES = [
  { name: 'jwt', re: /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g },
  { name: 'payment-provider-key', re: /\b[sp]k_(live|test)_[A-Za-z0-9]{10,}/g },
  { name: 'openai-key', re: /\bsk-(proj-)?[A-Za-z0-9_-]{20,}/g },
  { name: 'aws-access-key', re: /\bAKIA[0-9A-Z]{16}\b/g },
  { name: 'github-token', re: /\bgh[pousr]_[A-Za-z0-9]{20,}/g },
  { name: 'private-key-block', re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/g },
  { name: 'age-secret-key', re: /AGE-SECRET-KEY-1[0-9A-Z]{20,}/g },
  { name: 'connection-string-with-password', re: /\b(postgres|postgresql|mysql|mongodb(\+srv)?|redis):\/\/[^:\s/]+:[^@\s]+@/g },
  { name: 'hosted-supabase-project', re: /\b[a-z]{20}\.supabase\.(co|in)\b/g },
  { name: 'email-address', re: /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g,
    allow: (m) => /@example\.(com|org|net)$/i.test(m) },
  { name: 'non-synthetic-uuid', re: /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi,
    allow: (m) => m.startsWith('00000000-') },
];

function loadDenylist(path) {
  if (!existsSync(path)) return null;
  return readFileSync(path, 'utf8')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'))
    .map((l, i) => ({
      name: `denylist entry #${i + 1}`,
      re: l.startsWith('re:') ? new RegExp(l.slice(3), 'gi')
                             : new RegExp(l.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'),
    }));
}

function* walk(dir) {
  for (const entry of readdirSync(dir)) {
    if (SKIP_DIRS.has(entry)) continue;
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) yield* walk(full);
    else if (!SKIP_FILES.has(entry)) yield full;
  }
}

function scan(root, rules) {
  const findings = [];
  let files = 0;
  for (const file of walk(root)) {
    const buf = readFileSync(file);
    if (buf.includes(0)) continue;               // binary
    files += 1;
    const lines = buf.toString('utf8').split(/\r?\n/);
    lines.forEach((line, i) => {
      for (const rule of rules) {
        rule.re.lastIndex = 0;
        let m;
        while ((m = rule.re.exec(line)) !== null) {
          if (!(rule.allow && rule.allow(m[0]))) {
            findings.push({ file: relative(root, file), line: i + 1, col: m.index + 1, rule: rule.name });
          }
          if (m[0].length === 0) rule.re.lastIndex += 1;
        }
      }
    });
  }
  return { findings, files };
}

function selfTest() {
  const dir = mkdtempSync(join(tmpdir(), 'scrub-selftest-'));
  // Every sample is assembled at run time, so this file never contains a match
  // for its own rules.
  const j = (...p) => p.join('');
  const samples = {
    'jwt': j('eyJ', 'hbGciOiJIUzI1NiJ9', '.', 'eyJzdWIiOiIxMjM0NTY3ODkwIn0', '.', 'abcdefghijklmnop'),
    'payment-provider-key': j('sk', '_live_', 'abcdefghijklmnop1234'),
    'openai-key': j('sk', '-proj-', 'abcdefghijklmnopqrstuvwx1234'),
    'aws-access-key': j('AK', 'IA', 'ABCDEFGHIJKLMNOP'),
    'github-token': j('gh', 'p_', 'abcdefghijklmnopqrstuvwxyz12'),
    'private-key-block': j('-----BEGIN ', 'RSA PRIVATE', ' KEY-----'),
    'age-secret-key': j('AGE-SECRET', '-KEY-1', 'QQQQQQQQQQQQQQQQQQQQQQQQQ'),
    'connection-string-with-password': j('postgres', '://user:', 'hunter2', '@db.internal:5432/app'),
    'hosted-supabase-project': j('abcdefghijklmnopqrst', '.supabase', '.co'),
    'email-address': j('someone', '@', 'company', '.io'),
    'non-synthetic-uuid': j('7c9e6679', '-7425-40de-944b-e07fc1f90ae7'),
    'denylist entry #1': j('Acme', 'Private', 'Customer'),
  };
  const clean = [
    'contact: you@example.com',
    'id: 00000000-0000-4000-a000-00000000000a',
    'SELECT (SELECT auth.uid());',
    'regex in docs: sk_(live|test)_ prefixes are refused',
  ].join('\n');

  const deny = join(dir, 'deny');
  writeFileSync(deny, '# test\nacmeprivatecustomer\n');
  const rules = [...RULES, ...loadDenylist(deny)];

  let failed = 0;
  for (const [rule, text] of Object.entries(samples)) {
    const sub = mkdtempSync(join(dir, 'case-'));
    writeFileSync(join(sub, 'sample.txt'), `before ${text} after\n`);
    const hit = scan(sub, rules).findings.some((f) => f.rule === rule);
    console.log(`${hit ? 'ok  ' : 'FAIL'}  fires on ${rule}`);
    if (!hit) failed += 1;
  }
  const cleanDir = mkdtempSync(join(dir, 'clean-'));
  writeFileSync(join(cleanDir, 'clean.txt'), clean);
  const quiet = scan(cleanDir, rules).findings.length === 0;
  console.log(`${quiet ? 'ok  ' : 'FAIL'}  quiet on clean text (example.com, synthetic ids, prose about rules)`);
  if (!quiet) failed += 1;

  rmSync(dir, { recursive: true, force: true });
  const total = Object.keys(samples).length + 1;
  console.log(failed ? `SELF-TEST FAILED: ${failed}/${total}` : `SELF-TEST PASSED: ${total}/${total}, both directions`);
  return failed ? 1 : 0;
}

function main() {
  const args = new Set(process.argv.slice(2));
  if (args.has('--self-test')) process.exit(selfTest());

  const denyPath = join(ROOT, '.scrub-denylist');
  const deny = loadDenylist(denyPath);
  if (!deny) {
    const msg = 'local denylist .scrub-denylist not found — only the built-in patterns were checked';
    if (args.has('--release')) {
      console.error(`REFUSED: ${msg}. A release must be checked against it.`);
      process.exit(1);
    }
    console.warn(`warning: ${msg}`);
  }
  const { findings, files } = scan(ROOT, [...RULES, ...(deny || [])]);
  if (files === 0) {
    console.error('NOTHING CHECKED — no files were scanned. This is a failure, not a pass.');
    process.exit(1);
  }
  for (const f of findings) console.log(`${f.file}:${f.line}:${f.col}  ${f.rule}`);
  if (findings.length) {
    console.error(`SCRUB FAILED: ${findings.length} finding(s) in ${files} files. Values are not printed.`);
    process.exit(1);
  }
  console.log(`SCRUB PASSED: ${files} files, ${RULES.length} built-in rules${deny ? ` + ${deny.length} local denylist entries` : ''}.`);
}

main();
