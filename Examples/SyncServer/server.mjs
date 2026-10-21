// A reference sync server for HTTPSyncTransport (Node 24 or later, no dependencies).
//
//   node server.mjs [--port 8080] [--data sync-data.json]
//
// POST /sync/<collection>/push      {"changes": [...]}  ->  {"outcomes": {...}}
// GET  /sync/<collection>/changes?since=<token>&limit=<n>
//                                   ->  {"changes": [...], "token": "...", "hasMore": false}
//
// A page holds at most `limit` changes (100 by default, 1,000 at most) and 8 MiB of them.
//
// It keeps the data in memory and, with --data, in a JSON file written after every push. A push
// is answered, and its writes appear in pages, once the file was written; a failed write answers
// the push with status 500, and the next push that is saved keeps its changes too.
// It has no authentication: put it behind your own auth before you expose it.
import { createServer } from 'node:http';
import { readFile, rename, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import { Collection, ValidationError } from './collection.mjs';

export const MAX_BODY_BYTES = 1024 * 1024;
export const MAX_COLLECTIONS = 100;
const ROUTE = /^\/sync\/([A-Za-z0-9_-]{1,64})\/(push|changes)$/;

class HTTPError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function readBody(request) {
  const declared = Number(request.headers['content-length'] ?? 0);
  if (declared > MAX_BODY_BYTES) throw new HTTPError(413, `the body is larger than ${MAX_BODY_BYTES} bytes`);
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new HTTPError(413, `the body is larger than ${MAX_BODY_BYTES} bytes`);
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new HTTPError(400, 'the body is not valid JSON');
  }
}

function send(response, status, body) {
  const json = JSON.stringify(body);
  response.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(json) });
  response.end(json);
}

/**
 * Creates the HTTP server. `collections` maps collection names to `Collection`s and grows as
 * clients use new names; `save` is called with all of them after every push, and the push is
 * answered once it returns. Pages show a push's writes only after a save that followed it
 * succeeded: a device that pulled a write the server then lost in a restart would keep it for
 * good, as the write of another device or as its own push, applied, while every other device
 * goes without it.
 */
export function createSyncServer({ collections = new Map(), save = async () => {}, validate } = {}) {
  // Saves run one after another, so two pushes never write the data at the same time. A save
  // that fails (a full disk, a missing permission) answers its push with an error and leaves the
  // next one to run: that save writes every collection, the failed push's changes included.
  let saving = Promise.resolve();
  const saveAll = () => {
    const saved = saving.then(() => save(collections));
    saving = saved.catch(() => {});
    return saved;
  };
  const collection = (name) => {
    if (!collections.has(name)) {
      if (collections.size >= MAX_COLLECTIONS) throw new HTTPError(507, `at most ${MAX_COLLECTIONS} collections`);
      collections.set(name, new Collection({ validate }));
    }
    return collections.get(name);
  };

  return createServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://localhost');
      const match = ROUTE.exec(url.pathname);
      if (!match) throw new HTTPError(404, 'not found');
      const [, name, action] = match;
      if (action === 'push') {
        if (request.method !== 'POST') throw new HTTPError(405, 'use POST');
        const target = collection(name);
        const answer = target.push(await readBody(request), { publish: false });
        const written = target.sequence;
        await saveAll();
        target.publish(written);
        send(response, 200, answer);
      } else {
        if (request.method !== 'GET') throw new HTTPError(405, 'use GET');
        const limit = url.searchParams.has('limit') ? Number(url.searchParams.get('limit')) : undefined;
        send(response, 200, collection(name).changes(url.searchParams.get('since'), limit));
      }
    } catch (error) {
      if (error instanceof HTTPError) send(response, error.status, { error: error.message });
      else if (error instanceof ValidationError) send(response, 400, { error: error.message });
      else {
        console.error(error);
        send(response, 500, { error: 'internal error' });
      }
    }
  });
}

/** Loads collections saved by `saveToFile`. */
export async function loadFromFile(path) {
  let saved;
  try {
    saved = JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return new Map();
    throw error;
  }
  return new Map(Object.entries(saved).map(([name, state]) => [name, new Collection({ state })]));
}

/** Writes all collections to `path` atomically (temporary file, then rename). */
export async function saveToFile(path, collections) {
  const data = Object.fromEntries([...collections].map(([name, collection]) => [name, collection.snapshot()]));
  await writeFile(`${path}.tmp`, JSON.stringify(data));
  await rename(`${path}.tmp`, path);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const { values } = parseArgs({ options: { port: { type: 'string', default: '8080' }, data: { type: 'string' } } });
  const collections = values.data ? await loadFromFile(values.data) : new Map();
  const save = values.data ? (all) => saveToFile(values.data, all) : undefined;
  const server = createSyncServer({ collections, save });
  server.listen(Number(values.port), () => {
    console.log(`Sync server listening on http://localhost:${server.address().port}/sync/<collection>`);
  });
}
