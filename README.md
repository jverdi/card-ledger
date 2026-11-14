# Card Ledger

Personal native iPhone collection app with an optional private Codex research worker.

## Current status
**TestFlight 0.1.0 (4) is uploaded, processed and available to the `Personal evaluation` internal testing group as of November 14, 2026.** App Store Connect shows build 4 as `Testing`. Physical-device camera evaluation remains to be done.

Release commit: `958138967435d5650c8a2db18b615bffa80b1b05`. Successful release: https://github.com/jverdi/card-ledger/actions/runs/43624568746. Verification: 17 native unit tests, one end-to-end iPhone UI scan/reveal/edit/restart test, and 13 Python pricing tests pass in both verification and release workflows. The UI fixture runs real Vision rectangle detection and crop/OCR processing, with a deterministic test identity and slower fixture timing; camera hardware and live AI/search are not simulated as factual successes. Reveal and collection screenshots were inspected. The signed IPA was checked for bundle `com.jverdi.cardledger`, display name `Card Ledger` and iPhone-only device family.

The iPhone display name and all app screens use **Card Ledger**. Apple rejected the App Store Connect listing name because it is already in use; the temporary listing remains **Card Ledger by Verdi**. This listing conflict needs a user-selected available alternative or an Apple name claim.

Implemented: automatic front/back rectangle scanning and guided Photos import; two-sided 3D holographic reveal using a Metal shader; animated player/team reveal and collection-row insertion; automatic candidate research with a delayed spinner; forms restricted to editing saved cards; automatic perspective correction; manual four-corner crop and rotation; preserved originals and corrected copies; Vision OCR; on-device structured extraction from OCR; editable, explicitly confirmed identity; saved research; local collection; protected content-addressed photo files; atomic versioned index; SHA-256 backup integrity checks; legacy migration; search and sport/year/grade/tag/status/value filters; sorting; manual USD values with source/date; purchase cost/date and disposition proceeds/date; owned-only coverage totals; sold/gifted history; CSV; Keychain worker token; request cancellation; private Codex worker prototype; JSON schema validation and deterministic sold-comp calculation; quotas/cache; macOS CI; secure temporary signing and release workflow.

Still required for the complete automatic workflow:
- Deploy and authenticate a durable private HTTPS Codex worker, and configure the device connection.
- Benchmark real search retrieval; a schema-valid response is not proof of factual accuracy. Independently verify opened-page evidence and syndicated-sale duplicates.
- Direct multimodal image recognition and catalog candidate comparison. Current Apple Intelligence extraction uses OCR text, with manual fallback.
- Durable resumable processing, large-collection memory/performance checks, and recovery UX for corrupt stores.
- Real-device camera, crop, offline, upgrade and backup/restore testing with representative card photos.
- The first beta is available; complete live pricing and the remaining recognition/reliability checks before calling the entire app complete.

## Build
On a Mac with Xcode 26+: install XcodeGen, run `xcodegen generate`, then open CardLedger.xcodeproj. App targets iOS 26 for Foundation Models. Current recognition consumes OCR from both cropped faces; direct multimodal image understanding is not implemented.

Run `python3 -m unittest discover -s tests -v` for worker tests. iOS StoreTests cover persistence, import conflicts and corruption protection; these run on the GitHub macOS runner, not this Linux host. Tests also cover crop geometry, exact decimal values, checksum corruption and legacy photo migration.

## Private worker
Use an isolated trusted host/account with Codex CLI and your authenticated Codex session. Keep that authentication out of source control and off the iPhone. Install `worker/requirements.txt`. Set a random CARD_WORKER_TOKEN of at least 32 characters and run `python3 worker/worker.py`. It listens only on 127.0.0.1:8787. Put it behind a TLS reverse proxy/private network; do not expose the Python HTTP server directly. Configure the HTTPS endpoint and device token in app Settings.

The worker serializes requests, caps attempts at 30/day by default, caches seven days, validates identities and JSON, and computes only item-only USD sold comps. No cloud photo upload is performed. Set CARD_WORKER_DB to a private protected path; its cache contains query results. Review source-specific data retention terms before enabling ongoing storage. The worker is a prototype, not a hardened public service. A local integration attempt on 2026-11-14 could not initialize the Codex app-server because this Work runtime mounts its state filesystem read-only; ephemeral mode also failed. No successful live pricing lookup is claimed. Codex read-only sandbox and prompt restrictions do not replace process/container isolation or website evidence validation.

## TestFlight setup
Private repository: https://github.com/jverdi/card-ledger. App bundle `com.jverdi.cardledger`, App Store Connect app `6834848908`. The Developer Program agreement is accepted. An app-specific distribution profile, distribution certificate and Developer API key have been created; all signing and API credentials are stored as encrypted repository secrets. No credentials belong in source control or the app.

The manual TestFlight workflow runs Python and native tests, installs signing assets in a temporary keychain, archives, checks the exported IPA display name/bundle/device family, uploads, waits for Apple processing and removes runner signing assets. It uses a monotonic workflow run number as the build number. The `Personal evaluation` internal group contains the account owner and automatically receives builds. Build 4 has been verified in that group with Testing status; the owner tester was previously invited. The temporary local signing copies have been removed after successful upload; the encrypted CI secrets remain configured.

Required encrypted secrets: APPLE_TEAM_ID, PROFILE_NAME, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64, BUILD_CERTIFICATE_BASE64, BUILD_CERTIFICATE_PASSWORD, BUILD_PROVISION_PROFILE_BASE64. Refresh them through secure setup, never chat. Upstream Codex credentials are separate and are not configured by signing setup.

## Scan flow
Tap **+** to open “Scan front of card” immediately. The camera continuously detects four corners, checks card-like proportions, waits for focus/exposure and a stable 0.8-second hold, then captures automatically. No shutter or confirmation button is required. Lift the card out, flip it and hold the back steady; requiring a brief departure prevents instantly capturing the front twice.

Both detected rectangles are perspective-corrected. OCR runs on both sides concurrently, then on-device Apple Intelligence extracts a candidate identity from the combined text. Cropped front/back textures rotate in 3D with a presentation-only Metal holographic shine. Player/team animate into view when identification finishes, while the optional private Codex worker researches the candidate. A price spinner appears only if research is still pending three seconds after the timed identity reveal. Completion shrinks the presentation into a row and inserts it into the collection. Pricing failures save the scan with an unavailable/review state rather than inventing a value. Tap an existing row to edit the manual form.

Photo-library fallback follows the same front/back sequence and requires a complete detected rectangle. Cancellation stops later insertion. Original evidence is preserved separately from corrected display copies. Reduce Motion disables continuous rotation and shader animation.

## Evaluation checklist
- Tap +: verify immediate front guidance, automatic capture, back guidance and automatic back capture, with no manual form or shutter.
- Test square objects, clipped edges, moving cards and a card left front-side-up: none should trigger an inappropriate next capture.
- Scan two distinct owned copies; restart in airplane mode and confirm preservation.
- Check both faces in the rotating reveal, player/team motion, collection insertion and final row fields. With a worker, test fast and slow pricing and its delayed spinner.
- Open a saved card to adjust corners or rotate; inspect originals for unchanged condition evidence.
- Review OCR and identity, confirm only exact cards, and verify uncertain parallels remain manual.
- Enter your own value, purchase cost and sale proceeds; verify owned totals exclude sold/gifted copies.
- Search/filter and export CSV. Export a photo backup, restore on a clean install and compare both sides.
- With an authenticated worker, verify actual source pages, stale/sparse evidence and failures. A missing or failed lookup must preserve saved data.
- Inspect TestFlight build number and report device/OS and any crash or camera issue.
