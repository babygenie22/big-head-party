# Put Big Head Party on your iPhone with TestFlight

GitHub builds, signs and uploads the app for you. You set four values once and never share them in chat.
Total time: about 15 minutes of clicking, then about 20 minutes of waiting for the first build.

App identity used by the project:
- **Bundle ID:** `com.domqinvestments.bigheadparty`
- **Display name:** Big Head Party

## 1. Register the bundle ID (2 minutes)
1. Open <https://developer.apple.com/account/resources/identifiers/list> and sign in with your developer account.
2. Click **+** → **App IDs** → **App** → Continue.
3. Description: `Big Head Party`. Bundle ID: **Explicit**, `com.domqinvestments.bigheadparty`.
4. Leave the capabilities unticked → Continue → Register.

## 2. Create the app in App Store Connect (2 minutes)
1. Open <https://appstoreconnect.apple.com/apps> → **+** → **New App**.
2. Platform **iOS**. Name: `Big Head Party`. App names must be unique on the App Store, so if it's taken try `Big Head Party Game`. The name on your home screen stays "Big Head Party" either way.
3. Language: English. Bundle ID: pick `com.domqinvestments.bigheadparty`. SKU: `bigheadparty`. Access: Full.

## 3. Create an App Store Connect API key (3 minutes)
1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys**.
2. Click **+**. Name: `GitHub Actions`. Access: **Admin**. Admin lets Xcode create the signing certificate and profile for you.
3. Click **Download API Key**. You get a file named `AuthKey_XXXXXXXXXX.p8`, and Apple only lets you download it once, so keep it safe.
4. Note the **Key ID** (next to the key) and the **Issuer ID** (at the top of the page).

## 4. Find your Team ID (1 minute)
<https://developer.apple.com/account> → **Membership details** → **Team ID** (10 characters).

## 5. Add four secrets to the GitHub repo (3 minutes)
Open <https://github.com/babygenie22/big-head-party/settings/secrets/actions> → **New repository secret** for each:

| Name | Value |
|---|---|
| `ASC_KEY_ID` | the Key ID from step 3 |
| `ASC_ISSUER_ID` | the Issuer ID from step 3 |
| `ASC_PRIVATE_KEY` | the **entire contents** of the `.p8` file. Open it in a text editor and copy everything, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
| `APPLE_TEAM_ID` | the Team ID from step 4 |

GitHub encrypts these. They never appear in logs, and nobody viewing the repo can read them.

## 6. Run the upload
<https://github.com/babygenie22/big-head-party/actions/workflows/testflight.yml> → **Run workflow** → **Run workflow**.
It takes about 10 minutes. When it's green, Apple processes the build for another 5–15 minutes.

You can also push a version tag (e.g. `git tag v0.2 && git push --tags`) to upload automatically.

## 7. Install on your iPhone
1. App Store Connect → your app → **TestFlight**. When the build shows "Ready to Submit" or "Ready to Test", open **Internal Testing** → **+** to create a group, then add yourself (and anyone on your developer team).
2. On your iPhone, install **TestFlight** from the App Store and sign in with the same Apple ID. Big Head Party appears there → **Install**.
3. To invite family who aren't on your developer team, use **External Testing**. Apple runs a quick review of the first external build, usually under a day. Then share the public link.

## If something fails
- **"Missing repository secrets"**: one of the four secrets in step 5 is missing or misspelled.
- **"No profiles for 'com.domqinvestments.bigheadparty' were found"** or **"Cloud signing permission error"**: the API key needs **Admin** access (step 3).
- **"No suitable application records were found"**: create the app in App Store Connect (step 2) with exactly this bundle ID.
- **Agreements**: App Store Connect → **Business** must show the free apps agreement as active.
- Each run's `testflight-logs` artifact has the full Xcode output. Send me the error and I'll fix it.
