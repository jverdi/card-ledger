# Card Ledger

Personal native iPhone collection app with an optional private Codex research worker.

## Current status
Native iOS builds and simulator tests pass, including manual photo adjustment and ownership values. All 12 Python valuation tests pass. The first signed IPA was archived and exported successfully; Apple rejected its iPad orientation metadata. The device-family setting is corrected and the exported IPA is now checked before upload. All 10 native unit tests pass, including photo checksum corruption and legacy migration. The second release stopped before upload because Fastlane resolved the IPA-check script relative to its own directory; the script path is now explicit. A new release is being validated. TestFlight availability is not yet confirmed.

The iPhone display name and all app screens use **Card Ledger**. Apple rejected the App Store Connect listing name because it is already in use; the temporary listing remains **Card Ledger by Verdi**. This listing conflict needs a user-selected available alternative or an Apple name claim.

Implemented: front/back camera and Photos import; automatic perspective correction; manual four-corner crop and rotation; preserved originals and corrected copies; Vision OCR; on-device structured extraction from OCR; editable, explicitly confirmed identity; saved research; local collection; protected content-addressed photo files; atomic versioned index; SHA-256 backup integrity checks; legacy migration; search and sport/year/grade/tag/status/value filters; sorting; manual USD values with source/date; purchase cost/date and disposition proceeds/date; owned-only coverage totals; sold/gifted history; CSV; Keychain worker token; request cancellation; private Codex worker prototype; JSON schema validation and deterministic sold-comp calculation; quotas/cache; macOS CI; secure temporary signing and release workflow.

Still required for the complete automatic workflow:
- Deploy and authenticate a durable private HTTPS Codex worker, and configure the device connection.
- Benchmark real search retrieval; a schema-valid response is not proof of factual accuracy. Independently verify opened-page evidence and syndicated-sale duplicates.
- Direct multimodal image recognition and catalog candidate comparison. Current Apple Intelligence extraction uses OCR text, with manual fallback.
- Durable resumable processing, large-collection memory/performance checks, and recovery UX for corrupt stores.
- Real-device camera, crop, offline, upgrade and backup/restore testing with representative card photos.
- Apple processing and internal tester availability must be verified before reporting the beta ready.

## Build
On a Mac with Xcode 26+: install XcodeGen, run `xcodegen generate`, then open CardLedger.xcodeproj. App targets iOS 26 for the text Foundation Models implementation; direct image understanding requires the later SDK and capability verification.

Run `python3 -m unittest discover -s tests -v` for worker tests. iOS StoreTests cover persistence, import conflicts and corruption protection; these run on the GitHub macOS runner, not this Linux host. Tests also cover crop geometry, exact decimal values, checksum corruption and legacy photo migration.

## Private worker
Use an isolated trusted host/account with Codex CLI and your authenticated Codex session. Keep that authentication out of source control and off the iPhone. Install `worker/requirements.txt`. Set a random CARD_WORKER_TOKEN of at least 32 characters and run `python3 worker/worker.py`. It listens only on 127.0.0.1:8787. Put it behind a TLS reverse proxy/private network; do not expose the Python HTTP server directly. Configure the HTTPS endpoint and device token in app Settings.

The worker serializes requests, caps attempts at 30/day by default, caches seven days, validates identities and JSON, and computes only item-only USD sold comps. No cloud photo upload is performed. Set CARD_WORKER_DB to a private protected path; its cache contains query results. Review source-specific data retention terms before enabling ongoing storage. The worker is a prototype, not a hardened public service. A local integration attempt on 2026-11-14 could not initialize the Codex app-server because this Work runtime mounts its state filesystem read-only; ephemeral mode also failed. No successful live pricing lookup is claimed. Codex read-only sandbox and prompt restrictions do not replace process/container isolation or website evidence validation.

## TestFlight setup
Private repository: https://github.com/jverdi/card-ledger. App bundle `com.jverdi.cardledger`, App Store Connect app `6834848908`. The Developer Program agreement is accepted. An app-specific distribution profile, distribution certificate and Developer API key have been created; all signing and API credentials are stored as encrypted repository secrets. No credentials belong in source control or the app.

The manual TestFlight workflow runs Python and native tests, installs signing assets in a temporary keychain, archives, checks the exported IPA display name/bundle/device family, uploads, waits for Apple processing and removes runner signing assets. It uses a monotonic workflow run number as the build number. The `Personal evaluation` internal group contains the account owner and automatically receives builds. A successful upload alone does not prove tester availability.

Required encrypted secrets: APPLE_TEAM_ID, PROFILE_NAME, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64, BUILD_CERTIFICATE_BASE64, BUILD_CERTIFICATE_PASSWORD, BUILD_PROVISION_PROFILE_BASE64. Refresh them through secure setup, never chat. Upstream Codex credentials are separate and are not configured by signing setup.

## Evaluation checklist
- Add a manual card and two distinct owned copies; restart in airplane mode and confirm preservation.
- Photograph both sides, adjust corners and rotate; inspect originals for unchanged condition evidence.
- Review OCR and identity, confirm only exact cards, and verify uncertain parallels remain manual.
- Enter your own value, purchase cost and sale proceeds; verify owned totals exclude sold/gifted copies.
- Search/filter and export CSV. Export a photo backup, restore on a clean install and compare both sides.
- With an authenticated worker, verify actual source pages, stale/sparse evidence and failures. A missing or failed lookup must preserve saved data.
- Inspect TestFlight build number and report device/OS and any crash or camera issue.
