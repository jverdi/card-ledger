# Card Ledger

Personal native iPhone collection app with an optional private Codex research worker.

## Current status
Source implementation checkpoint, NOT a validated release. Native macOS build verification is in progress. No TestFlight upload has occurred. All 12 Python valuation tests pass in GitHub Actions. Private repository: https://github.com/jverdi/card-ledger. This development host is Linux without Xcode or Swift.

Implemented source: camera and Photos import; automatic rectangle/perspective correction; original photo preservation; Vision OCR; Apple Foundation Models structured extraction from OCR; editable card details; confirmed-card pricing requests; local atomic versioned persistence; search, sport/status filtering and sorting; tags and locations; sold/gifted archive; deletion confirmation; JSON photo backup/import; CSV; Keychain worker credential; private authenticated Codex worker; schema validation and deterministic comp calculation; usage limits and seven-day cache; macOS CI and fastlane upload lane.

Remaining before calling functionality complete:
- Compile/fix Swift on Xcode, run simulator tests, then real camera and device tests.
- Add manual four-corner crop/rotation controls and direct multimodal image recognition; current recognition uses OCR text.
- Add confirmed catalog candidate comparison and optional licensed reference images.
- Add configurable multi-field filters, manual valuations and acquisition/disposition amounts.
- Move image blobs out of JSON to individual protected files before large-collection testing; current implementation rewrites embedded photos on save.
- Strengthen backup validation with image hashes and limits; test recovery and upgrades.
- Add durable scan/research task queue and cancellation.
- Benchmark live Codex retrieval on actual cards; schema correctness is not factual accuracy. Add tool-evidence URL verification and cross-venue duplicate detection.
- Decide guide-value fallback. Worker intentionally refuses an aggregate with fewer than five verified sales.
- Provision HTTPS worker, complete privacy/retention decisions and add integration tests.
- Add app icon, verify SDK/tool pins, configure Apple signing and App Store Connect record; upload and verify internal tester availability.

## Build
On a Mac with Xcode 26+: install XcodeGen, run `xcodegen generate`, then open CardLedger.xcodeproj. App targets iOS 26 for the text Foundation Models implementation; direct image understanding requires the later SDK and capability verification.

Run `python3 -m unittest discover -s tests -v` for worker tests. iOS StoreTests cover persistence, import conflicts and corruption protection; these have not run on this Linux host.

## Private worker
Use an isolated trusted host/account with Codex CLI and your authenticated Codex session. Keep that authentication out of source control and off the iPhone. Install `worker/requirements.txt`. Set a random CARD_WORKER_TOKEN of at least 32 characters and run `python3 worker/worker.py`. It listens only on 127.0.0.1:8787. Put it behind a TLS reverse proxy/private network; do not expose the Python HTTP server directly. Configure the HTTPS endpoint and device token in app Settings.

The worker serializes requests, caps attempts at 30/day by default, caches seven days, validates identities and JSON, and computes only item-only USD sold comps. No cloud photo upload is performed. Set CARD_WORKER_DB to a private protected path; its cache contains query results. Review source-specific data retention terms before enabling ongoing storage. The worker is a prototype, not a hardened public service. Codex read-only sandbox and prompt restrictions do not replace process/container isolation or website evidence validation.

## TestFlight setup
The private repository is created. Apple currently blocks app creation and signing resources pending the Account Holder’s acceptance of the updated Developer Program License Agreement. Once restored, register `com.jverdi.cardledger` in your Apple team, create its App Store Connect record and internal tester group. Run Verify first. On the trusted macOS release runner install the Apple Distribution certificate/private key and matching provisioning profile into a temporary keychain. Provide APPLE_TEAM_ID, PROFILE_NAME, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64 and a unique monotonically increasing BUILD_NUMBER in secure CI secrets/environment. The manual TestFlight workflow runs tests, installs a temporary keychain, uploads with fastlane, waits for processing and cleans up signing assets. Configure the additional secure secrets BUILD_CERTIFICATE_BASE64, BUILD_CERTIFICATE_PASSWORD and BUILD_PROVISION_PROFILE_BASE64; use an App Store distribution profile. This workflow is prepared but has not run. Alternatively run `bundle install`, `xcodegen generate`, then `bundle exec fastlane ios beta` on a trusted Mac. The API key authenticates upload, not code signing. Remove the temporary keychain/profile on completion. No secrets are included in this archive.

Verify processing, export compliance and group assignment in App Store Connect. A successful upload alone does not prove tester availability. Record build number and install confirmation before reporting ready. TestFlight builds expire after 90 days.

## Next continuation
Apple credentials must be configured via secure setup, never pasted into chat. Resume from the remaining checklist above and do not report a release until macOS CI and real-device checks have passed.
