# Getting the app onto the Nokia 5.3

## The APK
The repository's **Releases** page holds the installable file: open
`https://github.com/<your-account>/bike-sensor-doctor/releases` on the Nokia, tap the newest
`BikeSensorDoctor-buildNN.apk`, then tap **Open** on the download and **Install**. If Android asks, allow installs
from Chrome/Files ("Install unknown apps"). If Play Protect warns, choose "Install anyway" (it is an unsigned
self-built app).

Each push to the repository triggers GitHub Actions to compile the app (~6 minutes) and publish a new release.

## First run
1. Open **Bike Sensor Doctor** → tap **ALLOW** (Nearby devices permission) → turn Bluetooth on if asked.
2. Put the bike next to you with the pedals free to turn.
3. Tap **DIAGNOSE & FIX MY POWER METER**. Follow the big coloured instructions (KEEP STILL / PEDAL NOW).
4. If a dialog asks for approval of a fix, read the risk text and choose YES or NO — nothing is sent otherwise.
5. Read the result card. "Send report to Claude" shares the saved technical report if we need to troubleshoot.

## Live numbers
**Show live watts & cadence** connects to the meter and displays whatever the phone can decode. Values from the
standard Bluetooth service are labelled *verified*; values from the XDS private format are labelled *estimated*.
