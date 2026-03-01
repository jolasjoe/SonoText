# Release DMG notarization

The Release DMG workflow **always** signs and notarizes the app so people who install from the DMG are not blocked by macOS ("developer cannot be verified"). The workflow **fails** if the required Apple Developer secrets are not set, so releases only publish a DMG when it can be notarized.

## Requirements

- **Apple Developer account** (paid)
- **Developer ID Application** certificate (from [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list))
- **App-specific password** for notarization (from [App Store Connect → Users and Access → App-specific passwords](https://appleid.apple.com/account/manage))

## Repository secrets (required for releases)

Add these under **Settings → Secrets and variables → Actions**. The release workflow will fail with a clear error if any are missing.

| Secret | Description |
|--------|-------------|
| `APPLE_SIGNING_IDENTITY` | Full name of the Developer ID Application cert, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded `.p12` of the Developer ID Application certificate. Export the cert from Keychain as .p12, then run: `base64 -i YourCert.p12 -o p12.txt` and paste the contents. |
| `APPLE_CERTIFICATE_PASSWORD` | Password you set when exporting the .p12 |
| `APPLE_KEYCHAIN_PASSWORD` | Optional. Password for the temporary keychain created in CI (default: `signing`) |
| `APPLE_ID` | Apple ID email used for notarytool |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password (not your Apple ID password) |
| `APPLE_TEAM_ID` | 10-character Team ID (from developer.apple.com/account) |

## Flow

1. Build the app and create the bundle.
2. Import the .p12 into a temporary keychain and sign the app with **Developer ID** and `--options runtime`.
3. Zip the app, submit to Apple with `xcrun notarytool submit --wait`, then run `xcrun stapler staple` on the app.
4. Create the DMG from the signed, stapled app and upload it to the release.

Users who download the release DMG can open the app without Gatekeeper blocking or right-click → Open.

## Creating the Developer ID certificate

You must use a **Developer ID Application** certificate. **Do not use** an **Apple Development** certificate — that is for development only; release signing and notarization require Developer ID.

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list), click **+** and create a **Developer ID Application** certificate (not "Apple Development").
2. Download and double-click to add it to Keychain.
3. In Keychain Access, export the certificate (and its private key) as a `.p12`. Set a strong password.
4. Base64-encode it: `base64 -i YourExport.p12 | pbcopy` and paste into `APPLE_CERTIFICATE_BASE64`.
5. Set `APPLE_SIGNING_IDENTITY` to the cert’s full name (e.g. `Developer ID Application: Your Name (TEAMID)`). Run `security find-identity -v -p codesigning` and copy the **Developer ID Application** line.

## App-specific password

1. Go to [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords.
2. Generate a new password and use it for `APPLE_APP_SPECIFIC_PASSWORD`. Revoke it from the same page when you rotate secrets.

## Verifying notarization (after a release)

After the Release DMG workflow runs and uploads a DMG to a GitHub release:

1. **Download the DMG** from the release Assets (e.g. `SonoText-0.1.0-alpha.2.dmg`).
2. **Validate the staple** (confirms the notarization ticket is attached):
   ```bash
   xcrun stapler validate /path/to/SonoText-0.1.0-alpha.2.dmg
   ```
   You should see: `The validate action worked!`
3. **Optional:** Mount the DMG, then check the app’s Gatekeeper assessment:
   ```bash
   hdiutil attach /path/to/SonoText-0.1.0-alpha.2.dmg
   xcrun stapler validate /Volumes/SonoText/SonoText.app
   spctl -a -v -t install /Volumes/SonoText/SonoText.app
   ```
   `spctl` should report `accepted` and `source=Notarized Developer ID`. Then eject: `hdiutil detach /Volumes/SonoText`.

If any of these fail, the DMG or app is not correctly notarized/stapled.

## Testing notarization locally

To build a signed, notarized DMG on your Mac (same result as CI, without uploading):

1. **Create a notarytool keychain profile** (one-time). Use the same Apple ID, team ID, and app-specific password as in GitHub secrets:
   ```bash
   xcrun notarytool store-credentials "SonoText-Notary" \
     --apple-id "YOUR_APPLE_ID_EMAIL" \
     --team-id "YOUR_TEAM_ID" \
     --password "YOUR_APP_SPECIFIC_PASSWORD"
   ```
   When prompted for a keychain password, you can set one or leave it empty; the profile is stored in your login keychain.

2. **Run the release script** with your Developer ID identity and the profile name:
   ```bash
   export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
   export NOTARYTOOL_PROFILE="SonoText-Notary"
   ./scripts/build-dmg-release.sh
   ```
   The script builds the app, signs it, notarizes and staples the app, creates the DMG, signs and notarizes the DMG, then runs `stapler validate` on the DMG. Output goes to `output/SonoText-<version>.dmg` (or `output/SonoText-<version>-<prerelease>.dmg` if you pass `--prerelease alpha`).

3. **Quick test without notarization** (faster; DMG will not pass Gatekeeper on another Mac):
   ```bash
   export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
   ./scripts/build-dmg-release.sh --skip-notarize
   ```

To only test build + DMG layout without signing or notarization, use `./scripts/build-release-dmg.sh SonoText-local.dmg`; that produces an ad-hoc signed DMG in `output/`.
