#!/usr/bin/env node
// Inventory Final Cut Pro Motion templates without confusing motionVFX's catalog
// placeholders with downloaded templates. Optional network lookups add motionVFX preview
// media or map local tokens to the current collection catalog.
//
// usage:
//   fcp-templates.mjs
//   fcp-templates.mjs --provider motionvfx --downloaded
//   fcp-templates.mjs --kind title --find "lower third" --list
//   fcp-templates.mjs --token 51PI --previews --json
//   fcp-templates.mjs --provider motionvfx --collections --json

import { fcpxmlVersions, findFcpApps, listMotionTemplates } from './lib/fcp.mjs';
import { fetchMotionVfxCollections, fetchMotionVfxPreviews } from './lib/motionvfx.mjs';

const args = process.argv.slice(2);
const argOf = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const has = (name) => args.includes(name);

if (has('--help') || has('-h')) {
  console.log(`usage: fcp-templates.mjs [options]

Local inventory (offline):
  --kind title|transition|effect|generator
  --provider apple|motionvfx|third-party
  --availability downloaded|catalog-placeholder|unavailable|all
  --downloaded                 shorthand for --availability downloaded
  --category NAME              exact category
  --find TEXT                  search name, category, token, or uid
  --token TOKEN                exact motionVFX token
  --list                       print matching templates
  --json                       print structured output

motionVFX catalog (network):
  --previews                   add public still/video metadata for a shortlist
  --collections                map downloaded tokens to current collections
  --limit N                    cap output; --previews requires <= 24 candidates
`);
  process.exit(0);
}

const apps = findFcpApps();
if (!apps.length) {
  console.error('demo-video: no Final Cut Pro in /Applications.');
  process.exit(1);
}

const validKinds = new Set(['title', 'transition', 'effect', 'generator']);
const validProviders = new Set(['apple', 'motionvfx', 'third-party']);
const validAvailability = new Set(['downloaded', 'catalog-placeholder', 'unavailable', 'all']);
const kind = argOf('--kind');
const provider = argOf('--provider');
const availability = has('--downloaded') ? 'downloaded' : (argOf('--availability') ?? 'all');

if (kind && !validKinds.has(kind)) {
  console.error(`demo-video: --kind must be one of ${[...validKinds].join(', ')}.`);
  process.exit(1);
}
if (provider && !validProviders.has(provider)) {
  console.error(`demo-video: --provider must be one of ${[...validProviders].join(', ')}.`);
  process.exit(1);
}
if (!validAvailability.has(availability)) {
  console.error(`demo-video: --availability must be one of ${[...validAvailability].join(', ')}.`);
  process.exit(1);
}

const category = argOf('--category');
const find = argOf('--find')?.toLowerCase();
const token = argOf('--token')?.toUpperCase();
const limitArg = argOf('--limit');
const limit = limitArg === undefined ? null : Number(limitArg);
if (limit !== null && (!Number.isInteger(limit) || limit < 1)) {
  console.error('demo-video: --limit must be a positive integer.');
  process.exit(1);
}

const allTemplates = listMotionTemplates({ kind, availability: 'all' });
const filteredTemplates = allTemplates.filter((template) => {
  if (availability !== 'all' && template.availability !== availability) return false;
  if (provider && template.provider !== provider) return false;
  if (category && template.category !== category) return false;
  if (token && template.motionVfxToken !== token) return false;
  if (find) {
    const haystack = [template.name, template.category, template.motionVfxToken, template.uid]
      .filter(Boolean)
      .join(' ')
      .toLowerCase();
    if (!haystack.includes(find)) return false;
  }
  return true;
});
let templates = filteredTemplates;
if (limit !== null) templates = templates.slice(0, limit);

const countBy = (items, keys) => {
  const rows = new Map();
  for (const item of items) {
    const key = keys.map((field) => item[field]).join('\t');
    rows.set(key, (rows.get(key) ?? 0) + 1);
  }
  return [...rows.entries()]
    .map(([key, count]) => ({
      ...Object.fromEntries(key.split('\t').map((value, index) => [keys[index], value])),
      count,
    }))
    .sort((a, b) => keys.map((key) => a[key].localeCompare(b[key])).find((n) => n) ?? 0);
};

const summary = countBy(filteredTemplates, ['kind', 'provider', 'availability']);
let previews = null;
let collections = null;

try {
  if (has('--previews')) {
    const candidates = templates.filter(
      (template) =>
        template.provider === 'motionvfx' &&
        template.availability === 'downloaded' &&
        template.motionVfxToken
    );
    if (!candidates.length) {
      console.error(
        'demo-video: --previews found no downloaded motionVFX tokens. Catalog placeholders must be downloaded in mExtension first.'
      );
      process.exit(1);
    }
    if (candidates.length > 24) {
      console.error(
        `demo-video: --previews matched ${candidates.length} templates. Narrow with --find/--token/--kind or --limit (maximum 24).`
      );
      process.exit(1);
    }
    previews = await fetchMotionVfxPreviews(candidates.map((template) => template.motionVfxToken));
  }

  if (has('--collections')) {
    const downloadedTokens = allTemplates
      .filter(
        (template) =>
          template.provider === 'motionvfx' &&
          template.availability === 'downloaded' &&
          template.motionVfxToken
      )
      .map((template) => template.motionVfxToken);
    collections = await fetchMotionVfxCollections(downloadedTokens);
  }
} catch (error) {
  console.error(`demo-video: ${error.message}`);
  process.exit(1);
}

if (has('--json')) {
  console.log(
    JSON.stringify(
      {
        apps,
        fcpxml: fcpxmlVersions(),
        summary,
        filters: { kind: kind ?? null, provider: provider ?? null, availability, category: category ?? null, find: find ?? null, token: token ?? null },
        templates,
        ...(previews ? { previews } : {}),
        ...(collections ? { collections } : {}),
      },
      null,
      2
    )
  );
} else {
  console.log(`Final Cut Pro: ${apps.join(', ')}`);
  console.log(`FCPXML import versions: ${fcpxmlVersions().map((version) => version.version).join(', ')}`);
  console.log('\nMotion templates Final Cut can see:');
  for (const row of summary) {
    console.log(
      `  ${row.kind.padEnd(11)} ${row.provider.padEnd(12)} ${row.availability.padEnd(19)} ${String(row.count).padStart(5)}`
    );
  }

  if (has('--list') || category || find || token) {
    console.log(`\nMatches (${templates.length}):`);
    for (const template of templates) {
      const id = template.motionVfxToken ? ` [${template.motionVfxToken}]` : '';
      console.log(
        `  ${template.kind.padEnd(10)} ${template.availability.padEnd(19)} ${template.category}/${template.name}${id}`
      );
    }
  } else {
    console.log('\nUse --provider motionvfx --downloaded --list for usable motionVFX templates.');
  }

  if (previews) {
    console.log('\nmotionVFX previews:');
    for (const preview of previews) {
      if (preview.error) console.log(`  ${preview.token}: ${preview.error}`);
      else console.log(`  ${preview.token} ${preview.name}: ${preview.image?.url ?? 'no still'} | ${preview.video?.url ?? 'no video'}`);
    }
  }

  if (collections) {
    console.log('\nmotionVFX collection matches:');
    for (const collection of collections.sort((a, b) => b.downloadedCount - a.downloadedCount)) {
      console.log(`  ${collection.name}: ${collection.downloadedCount}/${collection.totalCount} downloaded`);
    }
  }
}
