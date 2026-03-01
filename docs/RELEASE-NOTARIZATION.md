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

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list), create a **Developer ID Application** certificate.
2. Download and double-click to add it to Keychain.
3. In Keychain Access, export the certificate (and its private key) as a `.p12`. Set a strong password.
4. Base64-encode it: `base64 -i YourExport.p12 | pbcopy` and paste into `APPLE_CERTIFICATE_BASE64`.

## App-specific password

1. Go to [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords.
2. Generate a new password and use it for `APPLE_APP_SPECIFIC_PASSWORD`. Revoke it from the same page when you rotate secrets.
