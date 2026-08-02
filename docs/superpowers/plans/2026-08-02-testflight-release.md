# TestFlight release workflow — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pushing a `v*` tag builds, signs, and uploads Paperweight to TestFlight.

**Architecture:** A second workflow alongside `ci.yml`, triggered on tag push. It writes the git-ignored signing override from a secret, archives with automatic provisioning driven by an App Store Connect API key, and exports straight to App Store Connect. Versions come from the tag and the run number rather than from tracked files.

**Tech Stack:** GitHub Actions on `macos-15`, XcodeGen, `xcodebuild`, App Store Connect API.

**Human prerequisites:** `docs/RELEASING.md` — the Apple-side setup and the six repository secrets. **Nothing in this plan works until those secrets exist.** Tasks 1–3 can be written and merged before then; Task 4 is the first that needs them.

## Global Constraints

- Do not modify `ci.yml`. It stays the PR gate; this is a separate workflow with a separate trigger.
- **No secret may ever be echoed, printed, or written to a file that outlives the job.** Use `::add-mask::` where a value is derived, and clean the temporary keychain in an `always()` step.
- The repo's `no-committed-team` guard must keep passing. It uses `git grep`, which searches tracked files only, so writing a git-ignored `Configs/Signing.local.xcconfig` at runtime is fine — but nothing may write a team ID into a tracked file.
- The `.xcodeproj` is generated and git-ignored; run `xcodegen generate` before any build.
- Local development must not change. A fresh clone with no `Signing.local.xcconfig` still generates and builds for the simulator.
- All three shipping targets — app, monitor, widget — must carry identical `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. App Store validation rejects an app whose extensions disagree with it.

---

### Task 1: Make the version settable from outside

Today `CFBundleVersion` is hardcoded to `4` in each `Info.plist`. TestFlight rejects a repeated build number, so the version has to come from the build, not the file.

**Files:**
- Modify: `project.yml`
- Modify: `Paperweight/Info.plist`, `PaperweightMonitor/Info.plist`, `PaperweightWidget/Info.plist`

- [ ] **Step 1: Add default version settings**

In `project.yml`, under `settings.base` (alongside `SWIFT_VERSION`), add:

```yaml
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
```

Putting them in `settings.base` gives every target the same values, which is what App Store validation requires.

- [ ] **Step 2: Point the Info.plists at them**

In each of the three shipping targets' `Info.plist`, replace the literal values:

```xml
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
```

- [ ] **Step 3: Verify the substitution actually happens**

Build, then read the version back out of the built product rather than trusting the source:

```bash
xcodegen generate && xcodebuild build -project Paperweight.xcodeproj -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO MARKETING_VERSION=9.9 CURRENT_PROJECT_VERSION=1234 2>&1 | tail -2
```

Then find the built `.app` under DerivedData and confirm with `defaults read .../Info.plist CFBundleVersion` that it reads `1234`, not `$(CURRENT_PROJECT_VERSION)` and not `4`. A plist that ships the literal variable name is a silent failure that only shows up as an App Store rejection.

Do the same for the monitor and widget `.appex` bundles inside the app.

- [ ] **Step 4: Confirm the default still works** — build with no overrides and confirm the products read `1.0` / `1`.

- [ ] **Step 5: Commit**

```bash
git add project.yml Paperweight/Info.plist PaperweightMonitor/Info.plist PaperweightWidget/Info.plist
git commit -m "build: take the version from build settings, not the plists"
```

---

### Task 2: The export options

**Files:**
- Create: `Configs/ExportOptions.plist`

- [ ] **Step 1: Write it**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
```

`destination: upload` makes `-exportArchive` hand the build to App Store Connect directly, so no separate `altool` or Transporter step is needed.

`manageAppVersionAndBuildNumber: false` is load-bearing: left at its default, Xcode helpfully rewrites the build number during export, which would silently defeat Task 1.

- [ ] **Step 2: Verify the method name against the installed Xcode**

Apple renamed this key's value (`app-store` → `app-store-connect`) and older toolchains reject the new spelling. Confirm against the toolchain the runner uses:

```bash
xcodebuild -help | grep -A40 "exportOptionsPlist" | head -60
```

If the installed Xcode documents `app-store` instead, use that and note it in the file as a comment. Do not guess — a wrong value fails at export, after the whole archive has been built.

- [ ] **Step 3: Commit** — `git commit -m "build: add App Store export options"`

---

### Task 3: The release workflow

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes secrets: `APPLE_TEAM_ID`, `DIST_CERT_P12`, `DIST_CERT_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`.

- [ ] **Step 1: Write the workflow**

Structure it as follows. Read `.github/workflows/ci.yml` first and match its house style — it favours explicit `set -euo pipefail`, comments explaining *why* a line is load-bearing, and failure paths that actually fail.

1. **Trigger:** `on: push: tags: ['v*']`, plus `workflow_dispatch` with an optional version input so a release can be re-run without re-tagging.
2. **Guard:** fail early and clearly if any required secret is empty. A missing secret otherwise surfaces as an inscrutable codesign error forty minutes in. Do not print the secret — check emptiness only.
3. **Derive the version:** strip the leading `v` from `github.ref_name` for `MARKETING_VERSION`; use `github.run_number` for `CURRENT_PROJECT_VERSION`.
4. **Run the tests first.** Do not ship a red build. Reuse `ci.yml`'s simulator-selection approach rather than pinning a device name — runner images rotate their simulator sets.
5. **Signing setup:**
   - Create a temporary keychain with a random password, unlock it, set a long timeout, and add it to the search list.
   - Decode `DIST_CERT_P12` and import with `security import -T /usr/bin/codesign`.
   - Run `security set-key-partition-list` — without it, codesign blocks on a UI prompt that never comes and the job hangs until it times out.
   - Write `Configs/Signing.local.xcconfig` containing `DEVELOPMENT_TEAM = ${{ secrets.APPLE_TEAM_ID }}`. This file is git-ignored, so the `no-committed-team` guard is unaffected.
   - Write the `.p8` to a path under `$RUNNER_TEMP`, never into the workspace.
6. **Archive:**

```bash
xcodebuild archive \
  -project Paperweight.xcodeproj \
  -scheme Paperweight \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$RUNNER_TEMP/Paperweight.xcarchive" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "${{ secrets.ASC_KEY_ID }}" \
  -authenticationKeyIssuerID "${{ secrets.ASC_ISSUER_ID }}" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
```

7. **Export and upload:** `xcodebuild -exportArchive` with the same three authentication flags and `-exportOptionsPlist Configs/ExportOptions.plist`.
8. **Clean up in an `always()` step:** delete the temporary keychain and the `.p8`. A leaked signing identity on a shared runner is the failure mode that matters here, so this must run even when the build fails.
9. **Upload the `.xcarchive` as an artifact on failure only** — it is large, and on success the build is already in App Store Connect.

- [ ] **Step 2: Lint the workflow**

```bash
gh workflow view release.yml 2>/dev/null || python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml ok')"
```

- [ ] **Step 3: Confirm no secret can leak**

Re-read the workflow and check every place a secret appears. It must never be an argument to `echo`, never interpolated into a `run:` line that could be traced by `set -x`, and never written under `$GITHUB_WORKSPACE`. Report each secret and where it lands.

- [ ] **Step 4: Commit** — `git commit -m "ci: upload a tagged build to TestFlight"`

---

### Task 4: The first real run — needs the secrets in place

This is the first task that cannot be completed without the human prerequisites in `docs/RELEASING.md`.

- [ ] **Step 1: Confirm all six secrets exist**

```bash
gh secret list
```

Expect `APPLE_TEAM_ID`, `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8`, `DIST_CERT_P12`, `DIST_CERT_PASSWORD`. Only names and timestamps are listed; values are not retrievable, which is the point.

- [ ] **Step 2: Dry-run via `workflow_dispatch`** before tagging anything, so a failure doesn't leave a tag behind that has to be deleted and re-pushed.

- [ ] **Step 3: Read the failure, if any, against this list of the likely ones**

| Symptom | Cause |
|---|---|
| `No signing certificate "iOS Distribution" found` | `.p12` didn't import, or `set-key-partition-list` was skipped |
| `No profiles for 'media.baltar.paperweight' were found` | App ID missing, or the API key lacks App Manager |
| `Provisioning profile doesn't include the com.apple.developer.family-controls entitlement` | Family Controls not enabled on that App ID in the portal |
| Job hangs during codesign | `set-key-partition-list` missing — codesign is waiting on a UI prompt |
| `The bundle version must be higher than the previously uploaded version` | Build number reused; the run number should prevent this |
| `Cannot find app record` | Step 1 of `RELEASING.md` not done |

- [ ] **Step 4: Once green, tag for real** and confirm the build appears in App Store Connect under TestFlight.

- [ ] **Step 5: Open the PR**, closing the issue, and note in the body that the first successful upload needs its export-compliance answer set once in App Store Connect before testers can be invited.
