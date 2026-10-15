import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { MAX_BODY_BYTES, MAX_COLLECTIONS, createSyncServer, loadFromFile, saveToFile } from '../server.mjs';

let server;
let base;

before(async () => {
  server = createSyncServer();
  await new Promise((resolve) => server.listen(0, resolve));
  base = `http://localhost:${server.address().port}`;
});

after(() => server.close());

const timestamp = { wallTime: 1_700_000_000_000, counter: 1, nodeID: 'phone' };

async function push(collection, changes) {
  return fetch(`${base}/sync/${collection}/push`, { method: 'POST', body: JSON.stringify({ changes }) });
}

test('push and pull over HTTP', async () => {
  const id = randomUUID();
  const pushed = await push('notes', [{ id, recordID: 'a', operation: 'upsert', record: { id: 'a', text: 'Hi' }, timestamp }]);
  assert.equal(pushed.status, 200);
  const { outcomes } = await pushed.json();
  assert.equal(outcomes[id.toUpperCase()].status, 'accepted');
  const revision = outcomes[id.toUpperCase()].revision;
  assert.match(revision, /^[0-9a-f]{16}\.1$/);

  const pulled = await (await fetch(`${base}/sync/notes/changes`)).json();
  assert.deepEqual(pulled.changes, [{ recordID: 'a', record: { id: 'a', text: 'Hi' }, revision, sequence: 1, timestamp }]);
  assert.match(pulled.token, /^[0-9a-f]{16}\.1$/);
  assert.equal(pulled.epoch, revision.split('.')[0]);
  assert.equal(pulled.hasMore, false);
  const empty = await (await fetch(`${base}/sync/notes/changes?since=${pulled.token}`)).json();
  assert.deepEqual(empty.changes, []);
  assert.equal(empty.token, pulled.token);
});

test('collections are separate', async () => {
  await push('tasks', [{ id: randomUUID(), recordID: 1, operation: 'upsert', record: { id: 1 }, timestamp }]);
  const tasks = await (await fetch(`${base}/sync/tasks/changes`)).json();
  assert.deepEqual(tasks.changes.map((c) => c.recordID), [1]);
});

test('errors have status codes', async () => {
  assert.equal((await fetch(`${base}/sync/notes/other`)).status, 404);
  assert.equal((await fetch(`${base}/sync/../notes/changes`)).status, 404);
  assert.equal((await fetch(`${base}/sync/notes/push`)).status, 405);
  assert.equal((await fetch(`${base}/sync/notes/push`, { method: 'POST', body: '{' })).status, 400);
  assert.equal((await push('notes', [{ id: 'nope' }])).status, 400);
  const tooLarge = await fetch(`${base}/sync/notes/push`, { method: 'POST', body: 'x'.repeat(MAX_BODY_BYTES + 1) });
  assert.equal(tooLarge.status, 413);
});

test('the number of collections is limited', async () => {
  const limited = createSyncServer();
  await new Promise((resolve) => limited.listen(0, resolve));
  const url = `http://localhost:${limited.address().port}`;
  for (let index = 0; index < MAX_COLLECTIONS; index += 1) {
    assert.equal((await fetch(`${url}/sync/c${index}/changes`)).status, 200);
  }
  assert.equal((await fetch(`${url}/sync/one-too-many/changes`)).status, 507);
  limited.close();
});

test('collections survive a restart through the data file', async () => {
  const path = join(await mkdtemp(join(tmpdir(), 'sync-server-')), 'data.json');
  const collections = await loadFromFile(path);
  assert.equal(collections.size, 0);
  const first = createSyncServer({ collections, save: (all) => saveToFile(path, all) });
  await new Promise((resolve) => first.listen(0, resolve));
  const url = `http://localhost:${first.address().port}`;
  await fetch(`${url}/sync/notes/push`, {
    method: 'POST',
    body: JSON.stringify({ changes: [{ id: randomUUID(), recordID: 'kept', operation: 'upsert', record: { id: 'kept' }, timestamp }] }),
  });
  first.close();
  assert.match(await readFile(path, 'utf8'), /kept/);
  const reloaded = await loadFromFile(path);
  assert.deepEqual(reloaded.get('notes').changes(null).changes.map((c) => c.recordID), ['kept']);
});
