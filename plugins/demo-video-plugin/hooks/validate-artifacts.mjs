#!/usr/bin/env node
// PostToolUse: Write|Edit — validates demo artifacts the moment they are written.
//
// Dispatches to the real validators only for demo/storyboard.json and demo/timeline.json;
// silent for every other file. Validation failures exit 2 so Codex is shown the errors
// and fixes them immediately, instead of discovering the timing is nonsense after
// spending money on narration and an hour on capture.

import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
import { readHookInput, projectDir, fail, silent } from './lib/hookio.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const input = await readHookInput();
const root = projectDir(input);
const validators = [
  { file: 'demo/storyboard.json', match: /demo[/\\]storyboard\.json/, script: 'validate-storyboard.mjs' },
  { file: 'demo/timeline.json', match: /demo[/\\]timeline\.json/, script: 'validate-timeline.mjs' },
];

const filePath = input.tool_input?.file_path || input.tool_input?.path;
const changeText = String(input.tool_input?.command || input.tool_input?.patch || '');
const hits = validators.filter((validator) => {
  if (filePath && validator.match.test(filePath)) return true;
  return validator.match.test(changeText);
});
if (!hits.length) silent();

const reports = [];
for (const hit of hits) {
  const abs = filePath && hit.match.test(filePath) ? resolve(root, filePath) : join(root, hit.file);
  if (!existsSync(abs)) continue;

  const script = join(here, '..', 'scripts', hit.script);
  if (!existsSync(script)) continue;

  try {
    const out = execFileSync('node', [script, abs, '--project', root], {
      encoding: 'utf8',
      stdio: 'pipe',
    });
    if (out.trim()) reports.push(out.trim());
  } catch (err) {
    const message = [err.stdout, err.stderr].filter(Boolean).join('\n').trim();
    fail(
      message ||
        `demo-video: ${hit.script} failed on ${abs} but produced no output. Inspect it manually.`
    );
  }
}

if (reports.length) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: reports.join('\n') },
    })
  );
}
process.exit(0);
