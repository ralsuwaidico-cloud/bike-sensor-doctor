# BikeComputer iOS — one-time Apple setup (no Mac needed)

Everything is built on GitHub's macOS servers by `.github/workflows/ios.yml`. These are the only steps that need the
account holder personally. They are done once, in a web browser on Windows.

## 1. App Store Connect API key (lets the build server sign and upload)
1. appstoreconnect.apple.com → **Users and Access** → **Integrations** → **App Store Connect API** → Team Keys.
2. If asked, click **Request Access** and accept (account holder only).
3. **Generate API Key** → name `BikeComputer CI`, access **Admin** (needed for Apple's cloud-managed signing
   certificate) → Generate.
4. Note the **Key ID** and the **Issuer ID** (shown above the table). **Download** the `.p8` file — Apple allows
   this only once. Keep it private; never e-mail or chat it.

## 2. Team ID
developer.apple.com/account → **Membership details** → **Team ID** (10 characters).

## 3. Put the four values into GitHub secrets (encrypted; never visible again, never in logs)
github.com/ralsuwaidico-cloud/bike-sensor-doctor → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret**, four times:

| Name | Value |
|---|---|
| `ASC_KEY_ID` | Key ID from step 1 |
| `ASC_ISSUER_ID` | Issuer ID from step 1 |
| `ASC_PRIVATE_KEY` | open the `.p8` file in Notepad, copy **all** of it including the BEGIN/END lines |
| `APPLE_TEAM_ID` | Team ID from step 2 |

After this, the next build registers the bundle IDs `com.ralsuwaidico.bikecomputer` and
`com.ralsuwaidico.bikecomputer.watchkitapp` with HealthKit automatically.

## 4. Create the app record (Apple does not allow this through the API)
appstoreconnect.apple.com → **Apps** → **+** → **New App**: platform **iOS**, name e.g. `BikeComputer by Rashed`
(the App Store name must be unique worldwide; it is not public until you choose to publish), language English,
bundle ID **com.ralsuwaidico.bikecomputer**, SKU `bikecomputer`, user access **Full Access** → Create.

## 5. On the iPhone
Install **TestFlight** from the App Store and sign in with the same Apple ID. Builds appear there automatically
(private internal group "Rashed devices"; no Apple review, nothing public). Installing the iPhone app also offers
the Watch app (Watch app on the iPhone → BikeComputer → Install, if it does not install itself).
