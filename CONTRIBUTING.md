# Contributing

Thanks for taking the time to improve the Offline-First Framework.

## Reporting bugs

Open an issue with:

- what you did (the store configuration, the transport, the calls), what you expected and what
  happened,
- the `SyncReport`, `status` or error you got, and the server's answer if it is involved,
- platform and OS version (simulator or device) and Xcode version.

## Pull requests

1. Fork the repository and branch from `master`.
2. Keep each pull request focused on one change.
3. Run the tests:

    ```sh
    swift test
    xcodebuild test -scheme OfflineFirstFramework \
      -destination 'platform=iOS Simulator,name=iPhone 17'
    (cd Examples/SyncServer && npm test)
    ```

4. If you change sync behaviour, run the end-to-end suite against the reference server as well:

    ```sh
    node Examples/SyncServer/server.mjs &
    OFFLINE_FIRST_SERVER_URL=http://localhost:8080 swift test --filter EndToEnd
    ```

5. Add or update a test for every logic change. Store and sync tests use `InMemoryStorage`, a
   `TestClock` and the in-memory or scripted transports in
   `Tests/OfflineFirstFrameworkTests/Support.swift`, so they need no network and no waiting.
6. If you change the wire format of `HTTPSyncTransport`, update `Examples/SyncServer` and the
   "Server protocol" article in the same pull request.
7. If you change a README code sample, change the copy in
   `Examples/OfflineTodos/OfflineTodos/ReadmeSamples.swift` as well. That file is what gets
   compiled: by the example app, and by `swift test` through the symlink
   `Tests/OfflineFirstFrameworkTests/ReadmeExamples.swift`. Build the app with:

    ```sh
    cd Examples/OfflineTodos
    xcodebuild build -scheme OfflineTodos -destination 'generic/platform=iOS Simulator'
    ```

8. If a change affects the example app's screens, regenerate the screenshots with
   `scripts/capture-example-screens.sh`.
9. `README.md` has translations (`README.<language>.md`). Each one records the version of
   `README.md` it follows, and CI fails while a translation is behind. If you change `README.md`
   and cannot update the translations, say so in the pull request and they will be updated
   before it is merged.

## Code style

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- The package builds in the Swift 6 language mode; new code should not add warnings.
- Document public API with DocC comments (`///`); `xcodebuild docbuild` should report no
  warnings.
- Values from outside the app (server answers, files, names) are checked before use, and
  arithmetic on them must not trap.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `ci:`, `chore:`).

## License

By contributing you agree that your contributions are licensed under the MIT License.
