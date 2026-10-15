# Examples

## OfflineTodos

A to-do app for iOS and macOS that shows the framework at work: add, tick and delete to-dos,
switch the connection off with the **Online** toggle and watch the changes wait, switch it back
on and watch them sync, and press **Edit on another device** to change a to-do from a second
device on the same server. It uses the package from this checkout (a local package reference to
`../..`), so it always runs the current code.

Run it:

1. Open `Examples/OfflineTodos/OfflineTodos.xcodeproj` in Xcode 26 or later.
2. Choose the **OfflineTodos** scheme and an iPhone simulator or **My Mac** as the run
   destination.
3. Press **Run** (⌘R).

From the command line:

```sh
cd Examples/OfflineTodos
xcodebuild build -scheme OfflineTodos -destination 'generic/platform=iOS Simulator'
xcodebuild build -scheme OfflineTodos -destination 'platform=macOS'
```

By default the app syncs with an `InMemorySyncServer` inside the app, so it works without any
setup. To sync with a real server over HTTP, start the [reference server](SyncServer) and pass
its URL as a launch argument (**Product › Scheme › Edit Scheme… › Run › Arguments**):

```text
-serverURL http://localhost:8080/sync/todos
```

The app also shows the parts of an app that the README describes:

- [`DemoModel.swift`](OfflineTodos/OfflineTodos/DemoModel.swift) creates the store with a file
  in Application Support, starts automatic sync and wraps the transport in an offline switch.
- [`BackgroundRefresh.swift`](OfflineTodos/OfflineTodos/BackgroundRefresh.swift) syncs from a
  background app refresh task on iOS (`BGTaskSchedulerPermittedIdentifiers` is set in
  [`project.yml`](OfflineTodos/project.yml)).
- [`ReadmeSamples.swift`](OfflineTodos/OfflineTodos/ReadmeSamples.swift) holds the README's
  code samples. The package's test target compiles and runs the same file through the symlink
  `Tests/OfflineFirstFrameworkTests/ReadmeExamples.swift`.

The project file is made with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from
[`project.yml`](OfflineTodos/project.yml) and committed, so you only need XcodeGen after
editing `project.yml`. The README screenshots come from
[`scripts/capture-example-screens.sh`](../scripts/capture-example-screens.sh).

## SyncServer

A reference server for `HTTPSyncTransport` in about 270 lines of JavaScript for Node 24, with
its own tests. See [SyncServer/README.md](SyncServer/README.md).
