import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { mkdir, mkdtemp, readFile, rmdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { fileURLToPath } from 'node:url';
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
  assert.deepEqual(pulled.changes, [{ recordID: 'a', record: { id: 'a', text: 'Hi' }, revision, sequence: 1, timestamp, changeID: id }]);
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

test('large records reach a device that pulls from the beginning', async () => {
  // 17 pushes of four records of 250 KiB, each push within the 1 MiB body limit.
  const text = 'x'.repeat(250 * 1024);
  for (let first = 0; first < 68; first += 4) {
    const changes = [0, 1, 2, 3].map((offset) => {
      const id = `big-${first + offset}`;
      return { id: randomUUID(), recordID: id, operation: 'upsert', record: { id, text }, timestamp };
    });
    const answer = await (await push('large', changes)).json();
    assert.ok(Object.values(answer.outcomes).every((outcome) => outcome.status === 'accepted'));
  }
  const received = [];
  let token = null;
  for (;;) {
    const response = await fetch(`${base}/sync/large/changes${token ? `?since=${token}` : ''}`);
    const body = await response.text();
    assert.ok(Buffer.byteLength(body) <= 8 * 1024 * 1024 + 1024, `a page of ${Buffer.byteLength(body)} bytes`);
    const page = JSON.parse(body);
    received.push(...page.changes.map((c) => c.recordID));
    token = page.token;
    if (!page.hasMore) break;
  }
  assert.equal(received.length, 68);
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

/** Runs server.mjs in a process of its own on a free port, keeping its data in `data`. */
async function startServerProcess(data) {
  const script = fileURLToPath(new URL('../server.mjs', import.meta.url));
  const child = spawn(process.execPath, [script, '--port', '0', '--data', data], { stdio: ['ignore', 'pipe', 'ignore'] });
  const url = await new Promise((resolve, reject) => {
    let output = '';
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk) => {
      output += chunk;
      const port = /localhost:(\d+)/.exec(output)?.[1];
      if (port) resolve(`http://localhost:${port}`);
    });
    child.once('exit', (code) => reject(new Error(`the server exited with ${code}: ${output}`)));
  });
  return { url, kill: async () => {
    const exited = once(child, 'exit');
    child.kill('SIGKILL');
    await exited;
  } };
}

/** Pushes a new record `recordID` to the collection `notes` at `url` and returns the status. */
async function pushRecord(url, recordID) {
  const change = { id: randomUUID(), recordID, operation: 'upsert', record: { id: recordID }, timestamp };
  const response = await fetch(`${url}/sync/notes/push`, { method: 'POST', body: JSON.stringify({ changes: [change] }) });
  await response.arrayBuffer();
  return response.status;
}

/** A directory where the data file's temporary file goes makes every save fail until it is removed. */
async function failingSaves(data, body) {
  await mkdir(`${data}.tmp`);
  try {
    return await body();
  } finally {
    await rmdir(`${data}.tmp`);
  }
}

test('a save that failed does not stop later saves of the data file', async () => {
  const data = join(await mkdtemp(join(tmpdir(), 'sync-server-')), 'data.json');
  const server = await startServerProcess(data);
  try {
    assert.equal(await pushRecord(server.url, 'a'), 200);
    assert.equal(await failingSaves(data, () => pushRecord(server.url, 'b')), 500);
    // The disk takes writes again: the next push saves its change and the one that failed.
    assert.equal(await pushRecord(server.url, 'c'), 200);
    const saved = await loadFromFile(data);
    assert.deepEqual(saved.get('notes').changes(null).changes.map((c) => c.recordID), ['a', 'b', 'c']);
  } finally {
    await server.kill();
  }
});
