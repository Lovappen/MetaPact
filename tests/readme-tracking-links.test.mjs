import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, it } from 'node:test';

const root = resolve(import.meta.dirname, '..');
const readme = readFileSync(resolve(root, 'README.md'), 'utf8');
const devices = [
  ['yuanli-2-pro', '京东购买'],
  ['yuanli-2-mini', '京东购买'],
  ['yuanli-2-air', '京东购买'],
  ['blackhole-2-pro', '京东购买'],
  ['blackhole-plus', '京东购买'],
  ['blackhole-se', '京东购买'],
  ['blackhole-pro', '京东购买'],
  ['qianmian-2-pro', '京东购买'],
  ['qianmian-1', '淘宝购买'],
];

describe('README tracked outbound links', () => {
  it('routes all nine device purchase links through their dedicated MetaPact targets', () => {
    const trackingRefs = [...readme.matchAll(
      /^\[(device-[a-z0-9-]+)\]: https:\/\/metapact\.app\/r\/\?target=([a-z0-9-]+)&source=github-readme$/gm,
    )].map(([, label, target]) => [label, target]);

    assert.deepEqual(
      trackingRefs,
      devices.map(([target]) => [`device-${target}`, target]),
    );

    for (const [target, shopLabel] of devices) {
      assert.ok(readme.includes(`[${shopLabel}][device-${target}]`));
    }
  });

  it('routes the Heartbeat app README CTA through its own analytics event', () => {
    assert.match(
      readme,
      /href="https:\/\/metapact\.app\/r\/\?target=heartbeat-app-download&source=github-readme"/,
    );
  });
});
