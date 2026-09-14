// What the installed Final Cut Pro actually offers: FCPXML DTDs and Motion templates.
// Read from the app bundle and the user's Motion Templates folder, never assumed. motionVFX
// uses symlinks into .mExt-Placeholders for catalog entries that have not been downloaded;
// those entries are inventory-visible but must never be selected for an FCPXML export.

import { existsSync, lstatSync, readdirSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, relative, sep } from 'node:path';

const DTD_DIR = 'Contents/Frameworks/Interchange.framework/Versions/A/Resources';
const PETEMPLATES_DIR =
  'Contents/PlugIns/MediaProviders/MotionEffect.fxp/Contents/Resources/PETemplates.localized';

export const USER_MOTION_TEMPLATES_DIR = join(homedir(), 'Movies', 'Motion Templates.localized');

export const MOTION_TEMPLATE_KINDS = Object.freeze({
  title: { directory: 'Titles.localized', extension: '.moti' },
  transition: { directory: 'Transitions.localized', extension: '.motr' },
  effect: { directory: 'Effects.localized', extension: '.moef' },
  generator: { directory: 'Generators.localized', extension: '.motn' },
});

export function findFcpApps() {
  try {
    return readdirSync('/Applications')
      .filter((name) => /^Final Cut Pro.*\.app$/.test(name))
      .map((name) => join('/Applications', name));
  } catch {
    return [];
  }
}

const versionKey = (v) => v.split('.').map(Number).reduce((acc, n) => acc * 1000 + n, 0);

/** Every FCPXML version the installed FCP can import, newest first, with its DTD. */
export function fcpxmlVersions() {
  const found = new Map();
  for (const app of findFcpApps()) {
    const dir = join(app, DTD_DIR);
    if (!existsSync(dir)) continue;
    for (const file of readdirSync(dir)) {
      const m = /^FCPXMLv(\d+)_(\d+)\.dtd$/.exec(file);
      if (m) found.set(`${m[1]}.${m[2]}`, { app, dtd: join(dir, file) });
    }
  }
  return [...found.entries()]
    .map(([version, info]) => ({ version, ...info }))
    .sort((a, b) => versionKey(b.version) - versionKey(a.version));
}

const delocalize = (name) => name.replace(/\.localized$/, '');

function motionVfxToken(name) {
  return name.match(/(?:^|\s)([A-Z0-9]{4})$/)?.[1] ?? null;
}

function templateAvailability(file) {
  try {
    if (!lstatSync(file).isSymbolicLink()) return 'downloaded';
    const target = realpathSync(file);
    return target.split(sep).includes('.mExt-Placeholders') ? 'catalog-placeholder' : 'downloaded';
  } catch {
    return 'unavailable';
  }
}

function templateProvider({ source, category, availability, token }) {
  if (source === 'built-in') return 'apple';
  if (availability === 'catalog-placeholder') return 'motionvfx';
  if (/^(DesignStudio|motionVFX Freebies|mCaptions)$/i.test(category)) return 'motionvfx';
  // motionVFX's classic products conventionally use an m-prefixed category, while its
  // DesignStudio elements carry a stable four-character token in the template name.
  if (/^m[A-Z0-9]/.test(category) || (category === 'DesignStudio' && token)) return 'motionvfx';
  return 'third-party';
}

function walkTemplates(root, { prefix, source, kind, extension }) {
  const out = [];
  const walk = (dir) => {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
        continue;
      }
      if (!entry.name.endsWith(extension)) continue;

      const parts = relative(root, full).split(sep);
      const name = entry.name.slice(0, -extension.length);
      const category = parts.length > 2 ? delocalize(parts[0]) : '';
      const availability = source === 'built-in' ? 'downloaded' : templateAvailability(full);
      const token = motionVfxToken(name);
      const provider = templateProvider({ source, category, availability, token });
      out.push({
        name,
        category,
        kind,
        uid: `${prefix}/${MOTION_TEMPLATE_KINDS[kind].directory}/${parts.join('/')}`,
        source,
        provider,
        availability,
        ...(provider === 'motionvfx' && token ? { motionVfxToken: token } : {}),
      });
    }
  };
  walk(root);
  return out;
}

/**
 * All Motion templates Final Cut can see. By default this includes motionVFX catalog
 * placeholders so inventory can report them honestly; exporters should request downloaded.
 */
export function listMotionTemplates({
  fcpApps = findFcpApps(),
  userRoot = USER_MOTION_TEMPLATES_DIR,
  kind,
  availability = 'all',
} = {}) {
  const kinds = kind ? [kind] : Object.keys(MOTION_TEMPLATE_KINDS);
  const out = [];
  for (const candidateKind of kinds) {
    const spec = MOTION_TEMPLATE_KINDS[candidateKind];
    if (!spec) throw new Error(`unknown Motion template kind "${candidateKind}"`);
    for (const app of fcpApps) {
      out.push(
        ...walkTemplates(join(app, PETEMPLATES_DIR, spec.directory), {
          prefix: '...',
          source: 'built-in',
          kind: candidateKind,
          extension: spec.extension,
        })
      );
    }
    out.push(
      ...walkTemplates(join(userRoot, spec.directory), {
        prefix: '~',
        source: 'user',
        kind: candidateKind,
        extension: spec.extension,
      })
    );
  }

  const seen = new Set();
  return out
    .filter((template) => availability === 'all' || template.availability === availability)
    .filter((template) => (seen.has(template.uid) ? false : seen.add(template.uid)))
    .sort(
      (a, b) =>
        a.kind.localeCompare(b.kind) ||
        a.provider.localeCompare(b.provider) ||
        a.category.localeCompare(b.category) ||
        a.name.localeCompare(b.name)
    );
}

function same(value, wanted) {
  return String(value).localeCompare(String(wanted), undefined, { sensitivity: 'accent' }) === 0;
}

/**
 * Resolve an export-safe template selector. A selector may be a full FCPXML uid,
 * "Category/Name", exact name, or a motionVFX four-character token. Ambiguous names are
 * rejected so a generic name such as "Title" never silently picks an arbitrary pack.
 */
export function resolveMotionTemplate(
  selector,
  { kind, templates = listMotionTemplates({ kind, availability: 'downloaded' }) } = {}
) {
  const wanted = String(selector ?? '').trim();
  if (!wanted) return { template: null, matches: [], reason: 'empty' };
  const candidates = kind ? templates.filter((template) => template.kind === kind) : templates;
  const strategies = [
    (template) => template.uid === wanted,
    (template) => template.motionVfxToken && same(template.motionVfxToken, wanted),
    (template) => same(`${template.category}/${template.name}`, wanted),
    (template) => template.name === wanted,
    (template) => same(template.name, wanted),
  ];
  for (const strategy of strategies) {
    const matches = candidates.filter(strategy);
    if (matches.length === 1) return { template: matches[0], matches, reason: 'resolved' };
    if (matches.length > 1) return { template: null, matches, reason: 'ambiguous' };
  }
  return { template: null, matches: [], reason: 'missing' };
}

/** Downloaded built-in and user titles only; catalog placeholders are deliberately excluded. */
export function listTitleTemplates() {
  return listMotionTemplates({ kind: 'title', availability: 'downloaded' });
}

export function findTitleTemplate(name) {
  return resolveMotionTemplate(name, { kind: 'title' }).template;
}
