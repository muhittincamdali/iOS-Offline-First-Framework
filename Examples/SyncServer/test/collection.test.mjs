import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';
import { Collection, LIMITS, ValidationError } from '../collection.mjs';

const timestamp = { wallTime: 1_700_000_000_000, counter: 0, nodeID: 'phone' };

function change(overrides = {}) {
  return { id: randomUUID(), recordID: 'a', operation: 'upsert', record: { id: 'a', text: 'A' }, timestamp, baseRevision: null, ...overrides };
}

test('accepts new records and gives each write a revision with the epoch', () => {
  const notes = new Collection();
  const first = change();
  const { outcomes } = notes.push({ changes: [first] });
  assert.deepEqual(outcomes[first.id.toUpperCase()], { status: 'accepted', revision: `${notes.epoch}.1` });
  assert.equal(notes.sequence, 1);
});

test('answers a stale base revision with the current record', () => {
  const notes = new Collection();
  notes.push({ changes: [change()] });
  const stale = change({ record: { id: 'a', text: 'B' } });
  const answer = notes.push({ changes: [stale] }).outcomes[stale.id.toUpperCase()];
  assert.equal(answer.status, 'conflict');
  assert.deepEqual(answer.current, { recordID: 'a', record: { id: 'a', text: 'A' }, revision: `${notes.epoch}.1`, sequence: 1, timestamp });

  const fresh = change({ record: { id: 'a', text: 'B' }, baseRevision: `${notes.epoch}.1` });
  assert.equal(notes.push({ changes: [fresh] }).outcomes[fresh.id.toUpperCase()].status, 'accepted');
});

test('applies a repeated change ID only once', () => {
  const notes = new Collection();
  const once = change();
  const first = notes.push({ changes: [once] });
  const second = notes.push({ changes: [once] });
  assert.deepEqual(first, second);
  assert.equal(notes.sequence, 1);
});

test('deletes keep a revision so other devices learn about them', () => {
  const notes = new Collection();
  notes.push({ changes: [change()] });
  notes.push({ changes: [change({ operation: 'delete', record: undefined, baseRevision: `${notes.epoch}.1` })] });
  const page = notes.changes(`${notes.epoch}.1`);
  assert.deepEqual(page.changes, [{ recordID: 'a', revision: `${notes.epoch}.2`, sequence: 2, timestamp }]);
});

test('rejects records the validator refuses', () => {
  const notes = new Collection({ validate: (record) => (record.text ? null : 'Text is required') });
  const empty = change({ record: { id: 'a', text: '' } });
  assert.deepEqual(notes.push({ changes: [empty] }).outcomes[empty.id.toUpperCase()], { status: 'rejected', reason: 'Text is required' });
  assert.equal(notes.sequence, 0);
});

test('refuses new records beyond the limit but keeps accepting edits', () => {
  const notes = new Collection({ maxRecords: 1 });
  notes.push({ changes: [change()] });
  const extra = change({ recordID: 'b', record: { id: 'b' } });
  const answer = notes.push({ changes: [extra] }).outcomes[extra.id.toUpperCase()];
  assert.equal(answer.status, 'rejected');
  assert.match(answer.reason, /maximum of 1 records/);
  const edit = change({ record: { id: 'a', text: 'edited' }, baseRevision: `${notes.epoch}.1` });
  assert.equal(notes.push({ changes: [edit] }).outcomes[edit.id.toUpperCase()].status, 'accepted');
});

test('pages changes after a token', () => {
  const notes = new Collection();
  for (const id of ['a', 'b', 'c']) notes.push({ changes: [change({ recordID: id, record: { id } })] });
  const first = notes.changes(null, 2);
  assert.deepEqual(first.changes.map((c) => c.recordID), ['a', 'b']);
  assert.equal(first.hasMore, true);
  const second = notes.changes(first.token, 2);
  assert.deepEqual(second.changes.map((c) => c.recordID), ['c']);
  assert.equal(second.hasMore, false);
  assert.equal(notes.changes(second.token).token, `${notes.epoch}.3`);
  assert.equal(second.epoch, notes.epoch);
  // A token that is not one of this collection's starts from the beginning.
  assert.equal(notes.changes('../../etc').changes.length, 3);
  assert.equal(notes.changes(`${notes.epoch}.1`, 1e9).changes.length, 2);
});

test('starts from the beginning for a token of another epoch or one ahead', () => {
  const before = new Collection();
  for (const id of ['a', 'b', 'c']) before.push({ changes: [change({ recordID: id, record: { id } })] });
  const oldToken = before.changes(null).token;
  assert.deepEqual(before.changes(oldToken).changes, []);

  // A restarted in-memory server: empty again, with a new epoch.
  const restarted = new Collection();
  restarted.push({ changes: [change({ recordID: 'x', record: { id: 'x' } })] });
  assert.notEqual(restarted.epoch, before.epoch);
  const answer = restarted.changes(oldToken);
  assert.deepEqual(answer.changes.map((c) => c.recordID), ['x']);
  assert.equal(answer.token, `${restarted.epoch}.1`);

  // A plain revision number (tokens before epochs) and a position past the newest revision.
  assert.equal(restarted.changes('42').changes.length, 1);
  assert.equal(restarted.changes(`${restarted.epoch}.42`).changes.length, 1);
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
  assert.equal(notes.sequence, 0);
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

test('round-trips through a snapshot with a later epoch', () => {
  const notes = new Collection();
  const first = change();
  notes.push({ changes: [first] });
  const restored = new Collection({ state: JSON.parse(JSON.stringify(notes.snapshot())) });
  assert.ok(restored.epoch > notes.epoch);
  assert.deepEqual(restored.changes(null).changes, notes.changes(null).changes);
  // A token from before the restart starts the pull from the beginning.
  assert.deepEqual(restored.changes(notes.changes(null).token).changes.map((c) => c.recordID), ['a']);
  // The remembered answers are restored, so a repeated push is not applied again.
  assert.deepEqual(restored.push({ changes: [first] }), notes.push({ changes: [first] }));
  assert.equal(restored.sequence, 1);
  assert.throws(() => new Collection({ state: { sequence: 'x', records: [] } }), ValidationError);
  assert.throws(() => new Collection({ state: { sequence: 1, records: [{ recordID: 'a', revision: 'r', sequence: 2 }] } }), ValidationError);
});

test('a restored backup never hands out a revision again', () => {
  const live = new Collection();
  live.push({ changes: [change()] });
  const backup = JSON.parse(JSON.stringify(live.snapshot()));
  const v1 = `${live.epoch}.1`;
  const second = change({ record: { id: 'a', text: 'B' }, baseRevision: v1 });
  const lost = live.push({ changes: [second] }).outcomes[second.id.toUpperCase()].revision;

  // The server comes back from the backup: the second write is gone. A device that holds it
  // pushes an edit on top of it and must get a conflict, not overwrite the restored record.
  const restored = new Collection({ state: backup });
  const third = change({ record: { id: 'a', text: 'C' }, baseRevision: v1 });
  const accepted = restored.push({ changes: [third] }).outcomes[third.id.toUpperCase()];
  assert.equal(accepted.status, 'accepted');
  assert.notEqual(accepted.revision, lost);
  const stale = change({ record: { id: 'a', text: 'D' }, baseRevision: lost });
  assert.equal(restored.push({ changes: [stale] }).outcomes[stale.id.toUpperCase()].status, 'conflict');
});

test('reads files written before revisions had an epoch', () => {
  const legacy = { epoch: '0123456789abcdef', revision: 2, records: [{ recordID: 'a', record: { id: 'a' }, revision: 2, timestamp }] };
  const notes = new Collection({ state: legacy });
  assert.equal(notes.sequence, 2);
  assert.deepEqual(notes.changes(null).changes, [{ recordID: 'a', record: { id: 'a' }, revision: '2', sequence: 2, timestamp }]);
  const edit = change({ record: { id: 'a', text: 'new' }, baseRevision: '2' });
  assert.deepEqual(notes.push({ changes: [edit] }).outcomes[edit.id.toUpperCase()], { status: 'accepted', revision: `${notes.epoch}.3` });
});

test('keeps a timestamp from the future as it was pushed', () => {
  // The pushing device recognises its own write by the exact timestamp after a lost answer;
  // devices count a timestamp that is too far ahead as at their drift limit themselves.
  const notes = new Collection();
  const ahead = { wallTime: 4_000_000_000_000, counter: 3, nodeID: 'ahead' };
  const pushed = change({ timestamp: ahead });
  notes.push({ changes: [pushed] });
  assert.deepEqual(notes.changes(null).changes[0].timestamp, ahead);
  const conflict = notes.push({ changes: [change({ record: { id: 'a', text: 'B' } })] }).outcomes;
  assert.deepEqual(Object.values(conflict)[0].current.timestamp, ahead);
});

test('gives every start a later epoch of 16 hexadecimal digits', () => {
  const epochs = Array.from({ length: 50 }, () => new Collection().epoch);
  for (const epoch of epochs) assert.match(epoch, /^[0-9a-f]{16}$/);
  for (let index = 1; index < epochs.length; index += 1) assert.ok(epochs[index] > epochs[index - 1]);
  // A saved file from a clock that was ahead: the new epoch is later than the saved one too.
  const ahead = new Collection({ state: { epoch: '7000000000000000', sequence: 0, records: [] } });
  assert.equal(ahead.epoch, '7000000000000001');
});
