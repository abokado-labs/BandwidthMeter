# Bandwidth Meter

Bandwidth Meter is a compact macOS menu bar utility for understanding what your internet connection is doing right now.

It shows live upload and download rates in the menu bar, opens into a dark popover dashboard, and keeps local usage history so you can see which apps have been using bandwidth over the last hour, 12 hours, or 24 hours. It is designed as a companion to Model Meter, with the same lightweight menu bar pattern, settings window, privacy-first posture, and polished macOS feel.

## What It Shows

Bandwidth Meter focuses on the questions people actually have when their connection feels busy, slow, or strange:

- How much data is moving right now?
- Which apps are using my bandwidth?
- How much has each app downloaded or uploaded recently?
- Is my internet actually online?
- What network am I connected to?
- What public IP and advertised location does the outside world see, especially when a VPN is enabled?
- What was my latest network speed and quality test?

## Menu Bar

The menu bar display can show:

- download only
- upload only
- download and upload side by side
- download and upload stacked
- total traffic

Users can choose bytes or bits, auto/Kilo/Mega/Giga scale, rounded values, icon visibility, and menu bar font size. Stacked mode uses a compact fixed-width rendering so the menu bar item does not jump around as values change.

## First Run

On first launch, Bandwidth Meter shows a short onboarding window explaining what the app monitors and what it does not do.

The onboarding explains:

- live traffic is estimated from local network counters
- app usage history only covers time observed while Bandwidth Meter is running
- packet contents are not read
- usage history is stored locally
- Wi-Fi name access is optional
- macOS requires Location Services permission before any app can read the current Wi-Fi network name
- public IP location lookups contact `ipapi.co`

The app does not automatically request Wi-Fi name access on launch. Users can grant that optional permission from onboarding or Settings.

## Popover Dashboard

The popover is built for quick scanning:

- live download and upload rate
- 24-hour observed download and upload totals
- active network interface details
- Wi-Fi signal strength
- local IP address
- public IP address
- advertised public IP location
- internet online/offline status
- latest speed test result
- per-app bandwidth table
- app activity windows for 1 hour, 12 hours, and 24 hours

Apps remain visible in the selected time window even when they are no longer active. Active apps use live color; inactive apps are muted but still readable.

## App Details

Clicking an app opens an inspector designed to answer, "What is this thing, and why is it using bandwidth?"

The inspector can show:

- display name
- raw process name
- process ID
- resolved app bundle when available
- signing or bundle identity when available
- current upload and download rate
- recent observed upload and download totals
- a button to reveal the app in Finder when possible
- a web search button for unfamiliar processes

Known helper processes are grouped where practical, such as Safari/WebKit under Safari, Electron helpers under their host app, and common system daemons under System Services.

Users can optionally hide System Services from the dashboard app list. This only changes the visible app list; local totals are still retained so usage history remains accurate.

## Speed Testing

Bandwidth Meter uses Apple's built-in `networkQuality` command instead of requiring the Ookla Speedtest CLI.

The app can:

- run a speed test manually
- run speed tests automatically every 1, 3, 6, 12, or 24 hours
- show the latest test in the top dashboard
- store completed test history locally
- show best capable result from recent tests
- show an average across recent tests

Apple's `networkQuality` performs an out-of-network test against Apple's supported infrastructure. Results will not exactly match Ookla because the test endpoint and methodology are different.

## Internet Outage Detection

Bandwidth Meter passively checks whether the internet is reachable. When the internet appears down, the menu bar switches from bandwidth measurements to an outage state. While down, the app checks more frequently. When connectivity returns, it sends a local notification.

The outage check is lightweight and does not inspect packet contents.

## Privacy

Bandwidth Meter is designed to be local-first.

Privacy policy: https://abokadolabs.com/bandwidth-meter/privacy

- No packet contents are read.
- No traffic is routed, filtered, decrypted, or uploaded.
- Usage history is stored locally.
- Speed-test history is stored locally.
- Public IP location lookups contact `ipapi.co` to show the city, region, and country associated with the current public IP.
- Speed tests use Apple's built-in `networkQuality` command and contact Apple's test infrastructure.
- Wi-Fi network name access requires macOS Location Services permission because macOS treats SSID access as location-sensitive.

The app uses passive sampling and local system APIs. It does not install a Network Extension, privileged helper, VPN profile, packet filter, or kernel/system extension.

## Data Collection Approach

Bandwidth Meter samples lightweight per-process network counters while the app is running. It computes deltas between samples to estimate current upload and download rates and stores rolling local history in SQLite/Core Data.

Important caveat: historical totals only include usage observed while Bandwidth Meter was running. The app cannot reconstruct bandwidth usage from before it was launched.

## Settings

Settings are organized into:

- Display
- Monitoring
- Speed Test
- Updates
- About

Display settings control menu bar format, units, scale, rounding, font size, and icon visibility. Monitoring settings control launch at login, sampling interval, live-rate smoothing, grouping, hiding System Services, Wi-Fi name permission, history retention, and clearing locally stored usage history. Speed Test settings control manual and automatic test behavior. Updates handles Sparkle update checks. About links to Abokado Labs, support, and the privacy policy, and explains what the app does and does not collect.

Rate smoothing averages the live menu bar and dashboard speeds over a short window, such as 3 seconds. It makes the display calmer without changing the local usage totals.

## Updates

Bandwidth Meter is intended for direct distribution outside the Mac App Store. Sparkle is integrated for app updates, with automatic checks enabled and the appcast configured for `https://abokadolabs.com/bandwidth-meter/appcast.xml`. Release builds still need a signed archive and uploaded appcast contents before public update checks will return a downloadable update.

## Current Implementation Notes

The app is a native macOS menu bar app built with SwiftUI and AppKit.

Core components include:

- menu bar status item
- SwiftUI popover dashboard
- standalone SwiftUI settings window
- per-app bandwidth sampler
- app/process grouping
- Core Data persistence
- network identity lookup
- public IP location lookup
- internet availability monitor
- `networkQuality` speed test runner
- Sparkle update integration

The current bundle identifier is:

```text
com.bobkitchen.BandwidthMeter
```

## Known Limitations

- Wi-Fi SSID display depends on macOS Location Services authorization.
- Per-app attribution is best-effort because helper processes and system daemons do not always expose a clean parent app identity.
- Usage totals are locally observed, not OS-wide historical totals.
- Public IP location is an IP geolocation estimate and may represent a VPN endpoint, ISP routing location, or CDN/provider location rather than a physical device location.
- `networkQuality` results are not directly equivalent to Ookla Speedtest results.
