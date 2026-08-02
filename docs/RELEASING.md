# Releasing Paperweight to TestFlight

Cutting a release is one command:

```bash
git tag v1.1.0 && git push origin v1.1.0
```

That triggers `.github/workflows/release.yml`, which runs the tests, archives, signs, and
uploads the build to TestFlight. The tag's version becomes the marketing version; the build
number comes from the workflow run number, so it always increases.

Everything below is the one-time setup behind that.

---

## One-time setup

These steps need your Apple credentials, so they are yours to do — none of them can or
should be automated from CI, and none of the values below should ever be pasted into a
chat, a commit, or an issue. They go straight into GitHub's encrypted secrets.

### 1. App Store Connect — create the app record

<https://appstoreconnect.apple.com> → **Apps** → **+** → **New App**

- Platform: iOS
- Bundle ID: `media.baltar.paperweight`
- SKU: anything unique and private, e.g. `paperweight-001`
- Name and primary language: your call

Nothing can upload to TestFlight until this record exists.

### 2. Developer portal — confirm the identifiers

<https://developer.apple.com/account/resources/identifiers/list>

Three App IDs must exist, all under the same team:

| Bundle ID | Capabilities it needs |
|---|---|
| `media.baltar.paperweight` | Family Controls, NFC Tag Reading, App Groups |
| `media.baltar.paperweight.monitor` | Family Controls, App Groups |
| `media.baltar.paperweight.widget` | App Groups |

The App Group `group.media.baltar.paperweight` must exist and be ticked on all three.

Family Controls is a restricted entitlement — this is the piece Apple had to approve.
Confirm it is enabled on both the app and the monitor App IDs, not just requested.

### 3. Distribution certificate

<https://developer.apple.com/account/resources/certificates/list> → **+** → **Apple
Distribution**. Follow the CSR flow, download the `.cer`, and double-click it to land in
Keychain Access.

Then in Keychain Access, find the **private key** under it, right-click → **Export**, save
as `.p12`, and set a password you'll remember for a minute.

Convert it for GitHub:

```bash
base64 -i ~/Downloads/distribution.p12 | pbcopy
```

You now have the value for `DIST_CERT_P12`, and the password for `DIST_CERT_PASSWORD`.

Delete the `.p12` from Downloads afterwards.

### 4. App Store Connect API key

<https://appstoreconnect.apple.com/access/integrations/api> → **Team Keys** → **+**

- Name: `GitHub Actions`
- Access: **Admin**

**It must be Admin, not App Manager.** App Manager can upload builds, which is enough
for everything up to the final re-signing step — but it cannot create certificates or
provisioning profiles. Because this workflow lets Xcode mint the three distribution
profiles itself (see below), the key needs profile-creation rights, and Admin is the role
that grants them. An App Manager key fails at export with `Cloud signing permission
error`, followed by a misleading `No profiles for … were found`.

Be aware this is a broad grant: an Admin key can also manage users and agreements. If you
would rather not hand CI that much, the alternative is to pin the three provisioning
profiles as secrets and switch the workflow to manual signing — see the section below.

Download the `.p8`. **Apple only lets you download it once.** Note the **Key ID** shown in
the row, and the **Issuer ID** shown above the table.

```bash
base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Delete the `.p8` from Downloads afterwards.

### 5. Add the GitHub secrets

<https://github.com/erodewald/paperweight/settings/secrets/actions> → **New repository
secret**, six times:

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | Your 10-character Team ID (top-right of the developer portal) |
| `DIST_CERT_P12` | base64 from step 3 |
| `DIST_CERT_PASSWORD` | The password you set on the `.p12` |
| `ASC_KEY_ID` | Key ID from step 4 |
| `ASC_ISSUER_ID` | Issuer ID from step 4 |
| `ASC_KEY_P8` | base64 from step 4 |

That is the whole list. Note there are no provisioning-profile secrets — see below.

### 6. Fill in the first TestFlight compliance answers

The first upload lands in App Store Connect needing export-compliance answers before it
can go to testers. Paperweight uses no encryption beyond Apple's own, so the answer is
"no" — but you have to say so once, in the build's page under TestFlight.

---

## Troubleshooting

| Error | Cause |
|---|---|
| `Cloud signing permission error` / `No profiles for … were found` | The API key is not Admin. See step 4 — App Manager cannot create profiles. |
| `No signing certificate "iOS Distribution" found` | `DIST_CERT_P12` didn't import, or `DIST_CERT_PASSWORD` doesn't match |
| `Provisioning profile doesn't include the com.apple.developer.family-controls entitlement` | Family Controls not enabled on that App ID in the portal |
| Job hangs during codesign | The keychain partition list wasn't set — codesign is waiting on a prompt nobody can answer |
| `The bundle version must be higher than the previously uploaded version` | Build number reused for that marketing version |
| `Cannot find app record` | Step 1 wasn't done |

The archive is uploaded as a run artifact on failure, and Xcode's own distribution logs
are inside it — worth opening when the error text alone isn't enough.

---

## Why there are no provisioning profiles in that list

The workflow archives with `-allowProvisioningUpdates` and the App Store Connect API key,
which lets Xcode create and download the three distribution profiles itself at build time.

The alternative is exporting all three `.mobileprovision` files by hand, base64-ing them
into three more secrets, and re-doing it every time one expires — about an hour a year of
avoidable work.

The trade-off is that CI can create provisioning profiles in your developer account. For a
personal app with one developer that is the right side of the trade. If you'd rather CI
never touch the portal, the profiles can be pinned as secrets instead; say so and it's a
small change to the workflow.

The distribution **certificate** is still supplied explicitly rather than auto-created,
because certificates are limited per account and letting CI mint them is how you end up at
the cap wondering which of five certs is real.

---

## Versioning

`CFBundleShortVersionString` and `CFBundleVersion` are no longer hardcoded in the
`Info.plist` files. They read `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`,
which the release workflow sets:

- **Marketing version** comes from the tag: `v1.1.0` → `1.1.0`.
- **Build number** is the GitHub Actions run number plus an offset of `1000`, so the first
  automated build is `1001`. TestFlight rejects a build number it has seen before for the
  same marketing version, and `run_number` restarts at 1 for a newly added workflow — the
  offset is what keeps automated builds above the ones uploaded by hand before this
  existed. **Never lower it.** Build numbers may only ever go up.

All three targets get the same pair. App Store validation rejects an app whose extensions
disagree with it on version.

Local builds fall back to the defaults in `project.yml`, so nothing about day-to-day
development changes.

---

## Cutting a release

```bash
git tag v1.1.0 && git push origin v1.1.0
```

Watch it at <https://github.com/erodewald/paperweight/actions>. On success the build shows
up in App Store Connect under TestFlight within a few minutes, then takes Apple another
few to finish processing before it can be sent to testers.

To re-run a failed release, delete the tag and push it again — the run number will have
moved on, so the build number stays unique:

```bash
git tag -d v1.1.0 && git push origin :refs/tags/v1.1.0
git tag v1.1.0 && git push origin v1.1.0
```
