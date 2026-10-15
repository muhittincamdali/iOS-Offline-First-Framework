// The sync logic of one collection: revisions, conflict checks, idempotent pushes and paged
// pulls. It has no I/O, so the tests drive it directly.

export const LIMITS = Object.freeze({
  changesPerPush: 500,
  pageSize: 100,
  maxPageSize: 1000,
  rememberedChanges: 10_000,
  idLength: 256,
  nodeIDLength: 128,
  revisionLength: 64,
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class ValidationError extends Error {}

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
  #records = new Map(); // key -> { recordID, record, revision, timestamp }
  #revision = 0;
  #answers = new Map(); // change ID -> outcome, oldest first

  /** Optional check that returns a reason to reject a record, or null. */
  constructor({ validate = () => null, state } = {}) {
    this.validate = validate;
    if (state) this.#restore(state);
  }

  get revision() {
    return this.#revision;
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

  /** Returns changes after `after` (a revision number as a string), oldest first. */
  changes(after, limit = LIMITS.pageSize) {
    const since = /^\d{1,15}$/.test(after ?? '') ? Number(after) : 0;
    const size = Math.min(Math.max(1, Number.isSafeInteger(limit) ? limit : LIMITS.pageSize), LIMITS.maxPageSize);
    const changed = [...this.#records.values()].filter((entry) => entry.revision > since).sort((a, b) => a.revision - b.revision);
    const page = changed.slice(0, size);
    return {
      changes: page.map((entry) => this.#remote(entry)),
      cursor: String(page.at(-1)?.revision ?? since),
      hasMore: changed.length > page.length,
    };
  }

  /** A plain object for saving to disk. */
  snapshot() {
    return { revision: this.#revision, records: [...this.#records.values()] };
  }

  #apply(change) {
    const current = this.#records.get(keyOf(change.recordID));
    if (current && String(current.revision) !== change.baseRevision) {
      return { status: 'conflict', current: this.#remote(current) };
    }
    const reason = change.record ? this.validate(change.record) : null;
    if (reason) {
      return { status: 'rejected', reason, ...(current ? { current: this.#remote(current) } : {}) };
    }
    this.#revision += 1;
    this.#records.set(keyOf(change.recordID), {
      recordID: change.recordID,
      record: change.record,
      revision: this.#revision,
      timestamp: change.timestamp,
    });
    return { status: 'accepted', revision: String(this.#revision) };
  }

  #remote(entry) {
    const remote = { recordID: entry.recordID, revision: String(entry.revision), timestamp: entry.timestamp };
    if (entry.record) remote.record = entry.record;
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
    check(isPlainObject(state) && Number.isSafeInteger(state.revision) && Array.isArray(state.records), 'invalid saved state');
    this.#revision = state.revision;
    for (const entry of state.records) {
      validateRecordID(entry.recordID);
      this.#records.set(keyOf(entry.recordID), entry);
    }
  }
}
