// The sync logic of one collection: revisions, conflict checks, idempotent pushes and paged
// pulls. It has no I/O, so the tests drive it directly.

export const LIMITS = Object.freeze({
  changesPerPush: 500,
  pageSize: 100,
  maxPageSize: 1000,
  rememberedChanges: 10_000,
  recordsPerCollection: 100_000,
  idLength: 256,
  nodeIDLength: 128,
  revisionLength: 64,
  // How far ahead of the server's clock a pushed timestamp may be, in milliseconds.
  clockDrift: 300_000,
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TOKEN = /^([0-9a-f]{16})\.(\d{1,15})$/;

export class ValidationError extends Error {}

/** The last epoch handed out in this process, as a number. */
let lastEpoch = 0n;

/**
 * A new epoch, later than every earlier one: the time in microseconds since 1970, or one more
 * than the last epoch of this process or `after` (the epoch of a saved file) when that is
 * later, as 16 hexadecimal digits. Devices compare epochs, so a page from a stale replica of an
 * earlier run can be told from a new history.
 */
function nextEpoch(after = 0n) {
  const candidates = [BigInt(Date.now()) * 1000n, lastEpoch + 1n, after + 1n];
  lastEpoch = candidates.reduce((a, b) => (a > b ? a : b));
  return lastEpoch.toString(16).padStart(16, '0');
}

/** Map key for a record ID (a JSON string or number). */
function keyOf(recordID) {
  return JSON.stringify(recordID);
}

function check(condition, message) {
  if (!condition) throw new ValidationError(message);
}

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function validateRecordID(recordID) {
  const valid =
    (typeof recordID === 'string' && recordID.length > 0 && recordID.length <= LIMITS.idLength) ||
    Number.isSafeInteger(recordID);
  check(valid, 'recordID must be a non-empty string of at most 256 characters or a safe integer');
}

/** HLC timestamps must survive the trip through a JavaScript number unchanged. */
export function validateTimestamp(timestamp) {
  check(isPlainObject(timestamp), 'timestamp must be an object');
  const { wallTime, counter, nodeID } = timestamp;
  check(Number.isSafeInteger(wallTime) && wallTime >= 0, 'timestamp.wallTime must be a safe, non-negative integer');
  check(Number.isInteger(counter) && counter >= 0 && counter <= 0xffff_ffff, 'timestamp.counter must be a 32-bit unsigned integer');
  check(typeof nodeID === 'string' && nodeID.length > 0 && nodeID.length <= LIMITS.nodeIDLength, 'timestamp.nodeID must be a short string');
  return { wallTime, counter, nodeID };
}

export function validateChange(change) {
  check(isPlainObject(change), 'each change must be an object');
  check(typeof change.id === 'string' && UUID.test(change.id), 'change.id must be a UUID');
  validateRecordID(change.recordID);
  check(change.operation === 'upsert' || change.operation === 'delete', 'change.operation must be "upsert" or "delete"');
  if (change.operation === 'upsert') check(isPlainObject(change.record), 'an upsert needs a record object');
  const base = change.baseRevision ?? null;
  check(base === null || (typeof base === 'string' && base.length <= LIMITS.revisionLength), 'change.baseRevision must be a short string or null');
  return {
    id: change.id.toLowerCase(),
    recordID: change.recordID,
    record: change.operation === 'upsert' ? change.record : null,
    timestamp: validateTimestamp(change.timestamp),
    baseRevision: base,
  };
}

export class Collection {
  #records = new Map(); // key -> { recordID, record, revision, sequence, timestamp, changeID }
  #sequence = 0; // the number of writes; the newest write's position in the change feed
  #answers = new Map(); // change ID -> outcome, oldest first
  // Names this run of the collection in revisions and change tokens. Every start gets a new one,
  // also a start from saved data: the file may be an older backup, so the writes after it were
  // lost and their revisions and token positions would be handed out again. With a new epoch a
  // revision is never reused, and a token from before starts the pull from the beginning. Each
  // epoch is later than the ones before it (see nextEpoch).
  #epoch = nextEpoch();

  /**
   * `validate` returns a reason to reject a record, or null. `maxRecords` caps the records,
   * deleted ones included, so clients cannot grow the server's memory without limit. `now`
   * returns the server's time in milliseconds.
   */
  constructor({ validate = () => null, state, maxRecords = LIMITS.recordsPerCollection, now = () => Date.now() } = {}) {
    this.validate = validate;
    this.maxRecords = maxRecords;
    this.now = now;
    if (state) this.#restore(state);
  }

  get sequence() {
    return this.#sequence;
  }

  get epoch() {
    return this.#epoch;
  }

  /** Applies a push body and returns `{ outcomes }`. */
  push(body) {
    check(isPlainObject(body) && Array.isArray(body.changes), 'the body must be {"changes": [...]}');
    check(body.changes.length <= LIMITS.changesPerPush, `at most ${LIMITS.changesPerPush} changes per push`);
    const changes = body.changes.map(validateChange);
    const outcomes = {};
    for (const change of changes) {
      const answer = this.#answers.get(change.id) ?? this.#apply(change);
      this.#remember(change.id, answer);
      outcomes[change.id.toUpperCase()] = answer;
    }
    return { outcomes };
  }

  /**
   * Returns changes after `token` (`<epoch>.<sequence>`), oldest first, and the epoch. A token
   * of another epoch, or one ahead of this collection, starts from the beginning, so the client
   * gets every record again instead of waiting for writes that never come.
   */
  changes(token, limit = LIMITS.pageSize) {
    const match = TOKEN.exec(token ?? '');
    const position = match && match[1] === this.#epoch ? Number(match[2]) : 0;
    const since = position <= this.#sequence ? position : 0;
    const size = Math.min(Math.max(1, Number.isSafeInteger(limit) ? limit : LIMITS.pageSize), LIMITS.maxPageSize);
    const changed = [...this.#records.values()].filter((entry) => entry.sequence > since).sort((a, b) => a.sequence - b.sequence);
    const page = changed.slice(0, size);
    return {
      changes: page.map((entry) => this.#remote(entry)),
      token: `${this.#epoch}.${page.at(-1)?.sequence ?? since}`,
      hasMore: changed.length > page.length,
      epoch: this.#epoch,
    };
  }

  /** A plain object for saving to disk: the records and the remembered answers. */
  snapshot() {
    return { epoch: this.#epoch, sequence: this.#sequence, records: [...this.#records.values()], answers: [...this.#answers] };
  }

  #apply(change) {
    const current = this.#records.get(keyOf(change.recordID));
    if (current && current.revision !== change.baseRevision) {
      return { status: 'conflict', current: this.#remote(current) };
    }
    if (!current && this.#records.size >= this.maxRecords) {
      return { status: 'rejected', reason: `The collection holds the maximum of ${this.maxRecords} records.` };
    }
    const reason = change.record ? this.validate(change.record) : null;
    if (reason) {
      return { status: 'rejected', reason, ...(current ? { current: this.#remote(current) } : {}) };
    }
    this.#sequence += 1;
    const revision = `${this.#epoch}.${this.#sequence}`;
    this.#records.set(keyOf(change.recordID), {
      recordID: change.recordID,
      record: change.record,
      revision,
      sequence: this.#sequence,
      // Bounded by the server's clock, the one clock all devices share: a device whose clock
      // runs ahead wins over later edits on other devices for LIMITS.clockDrift at most.
      timestamp: this.#bounded(change.timestamp),
      // Sent back with the version, so the device that pushed it recognises its own write when
      // the answer was lost.
      changeID: change.id,
    });
    return { status: 'accepted', revision };
  }

  #bounded(timestamp) {
    const limit = this.now() + LIMITS.clockDrift;
    return timestamp.wallTime > limit ? { ...timestamp, wallTime: limit } : timestamp;
  }

  #remote(entry) {
    const remote = { recordID: entry.recordID, revision: entry.revision, sequence: entry.sequence, timestamp: entry.timestamp };
    if (entry.record) remote.record = entry.record;
    if (entry.changeID) remote.changeID = entry.changeID;
    return remote;
  }

  #remember(id, answer) {
    this.#answers.delete(id);
    this.#answers.set(id, answer);
    if (this.#answers.size > LIMITS.rememberedChanges) {
      this.#answers.delete(this.#answers.keys().next().value);
    }
  }

  #restore(state) {
    check(isPlainObject(state), 'invalid saved state');
    // Files written before revisions had an epoch call the counter `revision`.
    const sequence = state.sequence ?? state.revision;
    check(Number.isSafeInteger(sequence) && sequence >= 0 && Array.isArray(state.records), 'invalid saved state');
    this.#sequence = sequence;
    // The new epoch is also later than the saved one, should the clock have gone back since.
    if (typeof state.epoch === 'string' && /^[0-9a-f]{16}$/.test(state.epoch)) {
      this.#epoch = nextEpoch(BigInt(`0x${state.epoch}`));
    }
    for (const saved of state.records) {
      check(isPlainObject(saved), 'invalid saved record');
      validateRecordID(saved.recordID);
      // Such files also keep each record's revision as a plain number, which clients hold as
      // a string; it stays valid, and new writes get revisions with an epoch.
      const entry = typeof saved.revision === 'number' ? { ...saved, revision: String(saved.revision), sequence: saved.revision } : saved;
      check(typeof entry.revision === 'string' && Number.isSafeInteger(entry.sequence) && entry.sequence <= sequence, 'invalid saved record');
      check(entry.changeID === undefined || (typeof entry.changeID === 'string' && UUID.test(entry.changeID)), 'invalid saved record');
      this.#records.set(keyOf(entry.recordID), entry);
    }
    // The answers are kept, so a push repeated after a restart is still applied only once.
    const answers = state.answers ?? [];
    check(Array.isArray(answers), 'invalid saved answers');
    for (const pair of answers.slice(-LIMITS.rememberedChanges)) {
      check(Array.isArray(pair) && typeof pair[0] === 'string' && isPlainObject(pair[1]), 'invalid saved answer');
      this.#remember(pair[0], pair[1]);
    }
  }
}
