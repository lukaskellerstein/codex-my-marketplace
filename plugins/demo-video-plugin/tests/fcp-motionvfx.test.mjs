import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import test from 'node:test';

import { listMotionTemplates, resolveMotionTemplate } from '../scripts/lib/fcp.mjs';
import { fetchMotionVfxCollections, fetchMotionVfxPreview } from '../scripts/lib/motionvfx.mjs';

const touch = (file) => {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, '<ozml/>');
};

test('inventory distinguishes downloaded motionVFX templates from mExtension placeholders', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'demo-video-fcp-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));

  const downloaded = join(root, 'Titles.localized', 'DesignStudio', 'Lower Third ABCD', 'Lower Third ABCD.moti');
  const placeholder = join(root, 'Titles.localized', 'DesignStudio', '.mExt-Placeholders', 'Placeholder.moti');
  const catalog = join(root, 'Titles.localized', 'DesignStudio', 'Catalog EFGH', 'Catalog EFGH.moti');
  const transition = join(root, 'Transitions.localized', 'DesignStudio', 'Wipe IJKL', 'Wipe IJKL.motr');
  const thirdParty = join(root, 'Effects.localized', 'Acme', 'Bloom', 'Bloom.moef');
  touch(downloaded);
  touch(placeholder);
  mkdirSync(dirname(catalog), { recursive: true });
  symlinkSync(relative(dirname(catalog), placeholder), catalog);
  touch(transition);
  touch(thirdParty);

  const templates = listMotionTemplates({ fcpApps: [], userRoot: root, availability: 'all' });
  const byName = new Map(templates.map((template) => [template.name, template]));
  assert.equal(byName.get('Lower Third ABCD').provider, 'motionvfx');
  assert.equal(byName.get('Lower Third ABCD').availability, 'downloaded');
  assert.equal(byName.get('Lower Third ABCD').motionVfxToken, 'ABCD');
  assert.equal(byName.get('Catalog EFGH').availability, 'catalog-placeholder');
  assert.equal(byName.get('Wipe IJKL').kind, 'transition');
  assert.equal(byName.get('Bloom').provider, 'third-party');

  const downloadedOnly = listMotionTemplates({ fcpApps: [], userRoot: root, availability: 'downloaded' });
  assert.equal(downloadedOnly.some((template) => template.name === 'Catalog EFGH'), false);
  assert.equal(resolveMotionTemplate('ABCD', { kind: 'title', templates: downloadedOnly }).template.name, 'Lower Third ABCD');
  assert.equal(resolveMotionTemplate('DesignStudio/Lower Third ABCD', { kind: 'title', templates: downloadedOnly }).template.name, 'Lower Third ABCD');
});

test('preview metadata picks inspectable renditions and keeps template duration distinct', async () => {
  const fetchImpl = async () => ({
    ok: true,
    status: 200,
    json: async () => ({
      data: {
        results: {
          token: 'ABCD',
          name: 'Lower Third',
          detail_url: '/elements/ABCD',
          release_date: '2026-09-01',
          extra_data: { duration: '120', frameRate: '24' },
          grid_prev_img_data: {
            1920: { webp: { src: 'https://example.test/1920.webp', width: 1920, height: 1080 } },
            960: { webp: { src: 'https://example.test/960.webp', width: 960, height: 540 } },
          },
          grid_prev_video_data: {
            960: { h264: { src: 'https://example.test/960.mp4', width: 960, height: 540 } },
          },
          styles: [{ name: 'minimal' }],
          tags: [{ name: 'lower third' }],
        },
      },
    }),
  });

  const preview = await fetchMotionVfxPreview('abcd', { fetchImpl, maxWidth: 960 });
  assert.equal(preview.token, 'ABCD');
  assert.equal(preview.image.url, 'https://example.test/960.webp');
  assert.equal(preview.video.url, 'https://example.test/960.mp4');
  assert.equal(preview.templateDurationSeconds, 5);
  assert.equal(preview.detailUrl, 'https://www.motionvfx.com/design-studio/elements/ABCD');
});

test('collection mapping reports only collections containing downloaded tokens', async () => {
  const fetchImpl = async (url) => {
    const path = new URL(url).pathname;
    let results;
    let hasNext;
    if (path.endsWith('/collections')) {
      results = [
        { id: 1, name: 'Installed Pack', slug: 'installed-pack', type: 'system' },
        { id: 2, name: 'Other Pack', slug: 'other-pack', type: 'system' },
      ];
      hasNext = false;
    } else if (path.endsWith('/collections/installed-pack/elements')) {
      results = [
        { token: 'ABCD', name: 'One', fcp_kind: 'titles' },
        { token: 'EFGH', name: 'Two', fcp_kind: 'effects' },
      ];
    } else {
      results = [{ token: 'ZZZZ', name: 'Other' }];
    }
    return {
      ok: true,
      status: 200,
      json: async () => ({ data: { results, has_next: hasNext } }),
    };
  };

  const collections = await fetchMotionVfxCollections(['ABCD'], { fetchImpl, concurrency: 2 });
  assert.equal(collections.length, 1);
  assert.deepEqual(collections[0], {
    id: 1,
    name: 'Installed Pack',
    slug: 'installed-pack',
    type: 'system',
    downloadedCount: 1,
    totalCount: 2,
    coverage: 0.5,
    downloadedTokens: ['ABCD'],
    missing: [{ token: 'EFGH', name: 'Two', kind: 'effects' }],
  });
});
