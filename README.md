# BARTTime

A native SwiftUI app for BART: open a station, see upcoming trains ordered by next departure.

## Run on an iPhone or simulator

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `BART_API_KEY` using a key from [BART’s developer page](https://www.bart.gov/schedules/developers/api). The local file is ignored by Git.
2. On a Mac with Xcode 16 or newer, open **BARTTime.xcodeproj**.
3. Select the **BARTTime** scheme and an iPhone simulator, then press **Run** (⌘R).
4. For a physical iPhone, select your development team under **Signing & Capabilities**, choose a unique bundle identifier if needed, and select your connected phone. The app supports iOS 17 and newer.

The project is ready to open; no project generator, package download, or server is required. The root `Package.swift` is for testing the shared logic; open the `.xcodeproj` to run the app.

## Included

- Alphabetical list of all 50 stations, searchable by station name, abbreviation, or city.
- Tap a station to view each upcoming train in departure order, with a small line-color indicator, destination, direction, platform, and train length.
- Swipe a station or use its context menu to pin it at the top. Pins persist on the device; existing favorites are preserved. You can also pin or unpin from the station detail toolbar.
- Each train shows approximate arrivals at pinned stops ahead on its route: live departure wait plus the median scheduled journey duration for the same line, direction, and terminal destination. Stops behind you, on other branches, and beyond the train’s terminal are excluded. Unconfirmed stops are omitted; schedule lookup failures show a retry message.
- Filter trains by All, Northbound, or Southbound; the selection is saved separately for each station across app launches.
- Refresh every 30 seconds while the station detail screen is active; pull to refresh or tap the refresh button.
- Loading, retry, empty, offline, and stale-data states. Canceled trains are excluded. Previous data stays visible with a warning if refresh fails.
- Bundled station directory for offline browsing. Live station metadata refreshes from BART.
- Dark appearance, Dynamic Type layouts, VoiceOver labels, and an original app icon.

## Data behavior

This version uses BART's [legacy JSON departure API](https://api.bart.gov/docs/etd/etd.aspx) and [station API](https://api.bart.gov/docs/stn/stns.aspx). No API key values are committed. The app reads its key from the ignored local Xcode configuration; command-line tests can read `BART_API_KEY` from the environment. You can also pass a key to `BARTClient(key:)`. A build without a key still supports browsing the bundled station directory and reports a configuration error for live requests.

The times are **estimated departures**, not guaranteed arrivals. “Leaving” means under one minute until departure. Numbers are the latest BART estimates, not locally invented countdowns. The UI shows the source update time; responses more than two minutes old are labeled as last known times. BART delays already inform its estimates, so the app doesn't add delay seconds to them again.

The color indicator comes from each live estimate's color, not a hardcoded timetable. A line without predictions will not appear; an empty feed means no predictions, not a confirmed service suspension. BART [does not publish live predictions for the Oakland Airport Connector](https://www.bart.gov/schedules/developers/gtfs-realtime), so that station has an explicit information screen. The app uses no location permission and no analytics SDK.

BART recommends [GTFS Realtime](https://www.bart.gov/schedules/developers/gtfs-realtime) for new long-term integrations. JSON was used here for a small, dependency-free station board; `BARTServing` separates the data provider from the screens so a GTFS adapter can replace it later.

The bundled station catalog and test response were downloaded from BART on September 27, 2026. Test predictions are only in the test target and are never used as live data by the app. Data remains subject to [BART's developer license](https://www.bart.gov/schedules/developers/developer-license-agreement). The app is independent of BART and uses an original icon.

## Validation

Run the deterministic Swift tests on macOS or Linux:

```sh
swift test
```

Opt in to a real network check of the station directory and predictions at Montgomery, MacArthur, and Berryessa:

```sh
# Export BART_API_KEY in your shell first.
BART_LIVE_TEST=1 swift test
```

Build for the simulator on a Mac:

```sh
xcodebuild -project BARTTime.xcodeproj -scheme BARTTime \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

The included GitHub Actions workflow runs the core tests and simulator build when pushed to GitHub.

## Project layout

- `BARTTime/Views`: station list, station detail, train cards, and shared appearance.
- `BARTTime/Core`: models, decoding, HTTP client, observable state, and bundled stations.
- `Tests`: parser, network request, state, cancellation, and opt-in live checks.
- `scripts/generate_project.rb`: optional Xcode project regeneration (`gem install xcodeproj`).
- `scripts/AppIcon.svg`: editable source of the included 1024px icon.
