import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, it } from 'node:test';

const root = resolve(import.meta.dirname, '..');
const readme = readFileSync(resolve(root, 'README.md'), 'utf8');

describe('README tracked outbound links', () => {
  it('routes supported device links through MetaPact analytics with product targets', () => {
    assert.match(
      readme,
      /\[device-yuanli-2\]: https:\/\/metapact\.app\/r\/\?target=yuanli-2&source=github-readme/,
    );
    assert.match(
      readme,
      /\[device-blackhole-se\]: https:\/\/metapact\.app\/r\/\?target=blackhole-se&source=github-readme/,
    );
  });

  it('routes the Heartbeat app README CTA through its own analytics event', () => {
    assert.match(
      readme,
      /href="https:\/\/metapact\.app\/r\/\?target=heartbeat-app-download&source=github-readme"/,
    );
  });
});
