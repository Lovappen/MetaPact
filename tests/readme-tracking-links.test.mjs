import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, it } from 'node:test';

const root = resolve(import.meta.dirname, '..');
const readme = readFileSync(resolve(root, 'README.md'), 'utf8');
const devices = [
  ['yuanli-2-pro', '元力2 Pro', '京东购买', 'docs/assets/devices/yuanli-2-pro.jpg'],
  ['yuanli-2-mini', '元力2 Mini', '京东购买', 'docs/assets/devices/yuanli-2-mini.png'],
  ['yuanli-2-air', '元力2 Air', '京东购买', 'docs/assets/devices/yuanli-2-air.png'],
  ['blackhole-2-pro', '黑洞2 Pro', '京东购买', 'docs/assets/devices/black-hole-2-pro.png'],
  ['blackhole-plus', '黑洞 Plus', '京东购买', 'docs/assets/devices/black-hole-plus.jpg'],
  ['blackhole-se', '黑洞 Se', '京东购买', 'docs/assets/devices/black-hole-se-device.png'],
  ['blackhole-pro', '黑洞Pro', '京东购买', 'docs/assets/devices/black-hole-pro.png'],
  ['qianmian-2-pro', '千面2 Pro', '京东购买', 'docs/assets/devices/qianmian-2-pro.png'],
  ['qianmian-1', '千面1', '淘宝购买', 'docs/assets/devices/qianmian-1.png'],
];

describe('README tracked outbound links', () => {
  it('uses local images and tracked links on each device name and purchase action', () => {
    const deviceSection = readme.slice(readme.indexOf('## 适配设备'), readme.indexOf('## 文档'));

    assert.doesNotMatch(deviceSection, /<thead>|wdcdn\.qpic\.cn/);
    for (const [target, name, shopLabel, image] of devices) {
      const href = `https://metapact.app/r/?target=${target}&amp;source=github-readme`;

      assert.ok(deviceSection.includes(`<img src="${image}" alt="${name}" width="180">`));
      assert.ok(existsSync(resolve(root, image)), `${image} must exist`);
      assert.ok(deviceSection.includes(`<a href="${href}">${name}</a>`));
      assert.ok(deviceSection.includes(`<a href="${href}">${shopLabel}</a>`));
    }
  });

  it('routes the Heartbeat app README CTA through its own analytics event', () => {
    assert.match(
      readme,
      /href="https:\/\/metapact\.app\/r\/\?target=heartbeat-app-download&source=github-readme"/,
    );
  });
});
