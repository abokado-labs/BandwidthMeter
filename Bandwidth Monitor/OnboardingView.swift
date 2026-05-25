import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: BandwidthModel
    let onOpenPrivacy: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "speedometer")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bandwidth Meter")
                        .font(.title2.weight(.semibold))
                    Text("Live network speed and local app usage from your menu bar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                OnboardingPoint(
                    icon: "arrow.up.arrow.down",
                    title: "Shows live traffic",
                    detail: "Bandwidth Meter samples network counters once per second and shows current upload and download speed."
                )
                OnboardingPoint(
                    icon: "app.connected.to.app.below.fill",
                    title: "Groups traffic by app",
                    detail: "The dashboard lists apps and helper processes observed while Bandwidth Meter is running. It cannot reconstruct old usage from before the app was open."
                )
                OnboardingPoint(
                    icon: "lock.shield",
                    title: "Keeps usage history local",
                    detail: "Usage totals and speed-test history are stored on this Mac. Packet contents are not read, routed, decrypted, or uploaded."
                )
                OnboardingPoint(
                    icon: "location.circle",
                    title: "Wi-Fi name access is optional",
                    detail: "macOS requires location permission before any app can read the current Wi-Fi network name. Bandwidth Meter uses it only for the SSID label and does not store your location."
                )
                OnboardingPoint(
                    icon: "globe",
                    title: "Public IP lookup is external",
                    detail: "The public IP and advertised location card contacts ipapi.co so you can see where your connection or VPN appears to be located."
                )
            }

            Spacer()

            HStack {
                Button {
                    onOpenPrivacy()
                } label: {
                    Label("Privacy Policy", systemImage: "lock.doc")
                }

                Button {
                    model.requestWiFiNamePermission()
                } label: {
                    Label("Access Wi-Fi Name", systemImage: "wifi")
                }

                Spacer()

                Button("Continue") {
                    onComplete()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct OnboardingPoint: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
