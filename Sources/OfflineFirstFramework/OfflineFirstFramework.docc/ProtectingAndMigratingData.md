# Protecting and migrating data

Encrypt the store file, choose where it lives, change the record type safely, and recover from damaged files.

## Where the data lives

By default a store writes `Application Support/OfflineFirst/<name>.store` through a
``FileStore``. Pass another backend to change that:

```swift
let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.example")!
let storage = try FileStore(directory: shared.appending(path: "Sync"), protection: .complete)
let store = try OfflineStore<Todo>(name: "todos", storage: storage, transport: transport)
```

``InMemoryStorage`` keeps everything in memory for tests and previews. Store and file names are
checked by ``StorageName/validate(_:)``: letters, digits, `.`, `_` and `-` only, so a name can
never point outside the directory. ``FileStore`` refuses to read files above
``FileStore/maximumFileSize`` (256 MiB by default).

The store writes the whole file atomically after every change, and a change becomes visible
only after the write succeeded. That keeps the file consistent after a crash or a full disk;
it also means each write costs time proportional to the number of records. The design suits
collections up to tens of thousands of records. For larger data sets, split them into several
stores.

## Encryption

``StoreEncryption`` seals the file with AES-GCM. The easiest setup keeps a random 256-bit key
in the Keychain:

```swift
var configuration = OfflineStore<Todo>.Configuration()
configuration.encryption = try .keychain(account: "todos-key", keychain: KeychainStore(service: "com.example.todos"))
```

The store name is authenticated along with the data, so a file copied over another store's
file fails to open with ``OfflineFirstError/decryptionFailed`` instead of replacing its data.
A store with a key refuses unencrypted files; to encrypt an existing store, open it once with
`acceptsUnencryptedData: true` and remove the flag in the next release.

The Keychain item uses `afterFirstUnlockThisDeviceOnly` by default: it is not restored to a new
device from a backup, so a restored store cannot be decrypted there. Use
``CorruptionPolicy/moveAsideAndStartEmpty`` if the app should then start over and pull its data
from the server, or ``KeychainStore/Accessibility/afterFirstUnlock`` to include the key in
encrypted backups.

## Changing the record type

Adding an optional property needs nothing: `Decodable` reads old records without it. For other
changes, raise the schema version and add a ``RecordMigration`` that rewrites the stored JSON:

```swift
configuration.schemaVersion = 2
configuration.migrations = [
    // Version 2 renamed `done` to `isDone`.
    RecordMigration(to: 2) { record in
        record["isDone"] = record["done"] ?? false
        record["done"] = nil
    }
]
```

Migrations run once, in order, when the store opens a file with a lower version, on stored
records and on records waiting to sync. A file written by a higher schema version is never
opened or reset (``OfflineFirstError/unsupportedSchemaVersion(found:supported:)``), so an older
app version cannot drop fields it does not know.

## Damaged files

If the file cannot be decoded or decrypted, the initializer throws by default. With
``CorruptionPolicy/moveAsideAndStartEmpty`` the store renames the file to
`<name>.store.corrupt-<milliseconds>` and starts empty; the next sync pulls the server's data,
and local changes that had not been pushed are lost.

When a file can be read but holds odd values, the store repairs what is safe to repair:
duplicate record IDs (the last one wins), negative attempt counts, an empty device ID, and
counters close to `UInt64.max`, which are renumbered so they cannot overflow.
