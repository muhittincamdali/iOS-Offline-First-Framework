# Security policy

## Supported versions

Security fixes are made for the latest release. Version 1.0.0 is a different code base that
could not be used as a dependency and does not receive fixes.

## What counts as a vulnerability

The framework stores app data on the device, encrypts it on request and applies data that comes
from a server. Please report privately anything that makes it:

- read or write a file outside the directory of its `FileStore`, or open a store file that was
  copied over another store's file,
- reveal data from an encrypted store without the key, or accept a changed encrypted file,
- crash (a trap, an integer overflow, an out-of-range index) instead of throwing, for example on
  a damaged store file or on a server answer,
- loop without end, or use memory out of proportion to the data, on any server answer, including
  one from a server that has been taken over,
- let one device's timestamps win every later conflict, beyond what
  `Configuration.maximumClockDrift` documents.

The reference server in `Examples/SyncServer` has no authentication or rate limiting by design;
it is a sample to build on. Missing authentication there is not a vulnerability, but a way to
crash it or to exhaust its memory within its documented limits is worth a report.

## Reporting a vulnerability

Please report vulnerabilities privately, not in a public issue, pull request or discussion.

1. **Preferred:** open the repository's **Security** tab and choose
   **Report a vulnerability** ([how private reporting works](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately)).
2. **Or** email [muhittincamdali@gmail.com](mailto:muhittincamdali@gmail.com) with
   "Security" in the subject.

Include the version (tag or commit), the platform and OS version, the input that triggers the
problem and what happens.

## What happens next

- You get a reply within 7 days confirming that the report arrived.
- The issue is confirmed, fixed with a regression test, and released together with a GitHub
  security advisory on a disclosure date agreed with you.
- You are credited in the advisory unless you prefer not to be.
