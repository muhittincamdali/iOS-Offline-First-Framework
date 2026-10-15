import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';
import { Collection, LIMITS, ValidationError } from '../collection.mjs';

const timestamp = { wallTime: 1_700_000_000_000, counter: 0, nodeID: 'phone' };

function change(overrides = {}) {
  return { id: randomUUID(), recordID: 'a', operation: 'upsert', record: { id: 'a', text: 'A' }, timestamp, baseRevision: null, ...overrides };
}

test('accepts new records and bumps the revision', () => {
  const notes = new Collection();
  const first = change();
  const { outcomes } = notes.push({ changes: [first] });
  assert.deepEqual(outcomes[first.id.toUpperCase()], { status: 'accepted', revision: '1' });
  assert.equal(notes.revision, 1);
});

test('answers a stale base revision with the current record', () => {
  const notes = new Collection();
  notes.push({ changes: [change()] });
  const stale = change({ record: { id: 'a', text: 'B' } });
  const answer = notes.push({ changes: [stale] }).outcomes[stale.id.toUpperCase()];
  assert.equal(answer.status, 'conflict');
  assert.deepEqual(answer.current, { recordID: 'a', record: { id: 'a', text: 'A' }, revision: '1', timestamp });

  const fresh = change({ record: { id: 'a', text: 'B' }, baseRevision: '1' });
  assert.equal(notes.push({ changes: [fresh] }).outcomes[fresh.id.toUpperCase()].status, 'accepted');
});

test('applies a repeated change ID only once', () => {
  const notes = new Collection();
  const once = change();
  const first = notes.push({ changes: [once] });
  const second = notes.push({ changes: [once] });
  assert.deepEqual(first, second);
  assert.equal(notes.revision, 1);
});

test('deletes keep a revision so other devices learn about them', () => {
  const notes = new Collection();
  notes.push({ changes: [change()] });
  notes.push({ changes: [change({ operation: 'delete', record: undefined, baseRevision: '1' })] });
  const page = notes.changes('1');
  assert.deepEqual(page.changes, [{ recordID: 'a', revision: '2', timestamp }]);
});

test('rejects records the validator refuses', () => {
  const notes = new Collection({ validate: (record) => (record.text ? null : 'Text is required') });
  const empty = change({ record: { id: 'a', text: '' } });
  assert.deepEqual(notes.push({ changes: [empty] }).outcomes[empty.id.toUpperCase()], { status: 'rejected', reason: 'Text is required' });
  assert.equal(notes.revision, 0);
});

test('pages changes after a cursor', () => {
  const notes = new Collection();
  for (const id of ['a', 'b', 'c']) notes.push({ changes: [change({ recordID: id, record: { id } })] });
  const first = notes.changes(null, 2);
  assert.deepEqual(first.changes.map((c) => c.recordID), ['a', 'b']);
  assert.equal(first.hasMore, true);
  const second = notes.changes(first.cursor, 2);
  assert.deepEqual(second.changes.map((c) => c.recordID), ['c']);
  assert.equal(second.hasMore, false);
  assert.equal(notes.changes(second.cursor).cursor, '3');
  // A cursor that is not a revision number starts from the beginning.
  assert.equal(notes.changes('../../etc').changes.length, 3);
  assert.equal(notes.changes('1', 1e9).changes.length, 2);
});

test('refuses malformed changes', () => {
  const notes = new Collection();
  const cases = [
    { changes: 'nope' },
    { changes: [change({ id: 'not-a-uuid' })] },
    { changes: [change({ recordID: '' })] },
    { changes: [change({ recordID: 'x'.repeat(257) })] },
    { changes: [change({ operation: 'merge' })] },
    { changes: [change({ record: 'text' })] },
    { changes: [change({ timestamp: { ...timestamp, wallTime: 2 ** 63 } })] },
    { changes: [change({ timestamp: { ...timestamp, wallTime: -1 } })] },
    { changes: [change({ timestamp: { ...timestamp, counter: 2 ** 32 } })] },
    { changes: [change({ timestamp: { ...timestamp, nodeID: '' } })] },
    { changes: [change({ baseRevision: 'r'.repeat(65) })] },
    { changes: Array.from({ length: LIMITS.changesPerPush + 1 }, () => change()) },
  ];
  for (const body of cases) {
    assert.throws(() => notes.push(body), ValidationError);
  }
  assert.equal(notes.revision, 0);
});

test('remembers a bounded number of change IDs', () => {
  const notes = new Collection();
  const first = change({ recordID: 'first', record: { id: 'first' } });
  notes.push({ changes: [first] });
  for (let index = 0; index < LIMITS.rememberedChanges; index += 1) {
    notes.push({ changes: [change({ recordID: `r${index}`, record: { id: index } })] });
  }
  // The oldest answer was forgotten, so the change is now checked again and conflicts.
  assert.equal(notes.push({ changes: [first] }).outcomes[first.id.toUpperCase()].status, 'conflict');
});

test('round-trips through a snapshot', () => {
  const notes = new Collection();
  notes.push({ changes: [change()] });
  const restored = new Collection({ state: JSON.parse(JSON.stringify(notes.snapshot())) });
  assert.deepEqual(restored.changes(null), notes.changes(null));
  assert.throws(() => new Collection({ state: { revision: 'x', records: [] } }), ValidationError);
});
