//
//  LandingScreen.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 9/16/25.
//


import SwiftUI

struct LandingScreen: View {
    @AppStorage("hasSeenLanding") private var hasSeenLanding = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title + version
                    Text("the untitled jamming app")
                        .font(.largeTitle).bold()
                        .foregroundColor(.white)

                    Text("Version 1 • Research build")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Divider().background(Color.white.opacity(0.1))

                    // What is this?
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("What is this?")
                                .font(.headline)
                            Text("""
This is a **research project** exploring real-time loop jamming with open models:
- **Stable Audio Open Small** (“Jerry”) — hosted by us
- **Magenta Realtime** (“Darius”) — API hosted on Hugging Face (easy to duplicate and self-host)
""")
                        }
                        .foregroundColor(.white)
                    }
                    .groupBoxStyle(.landingCard)

                    // Model links
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Models & links")
                                .font(.headline)

                            LinkRow(
                                title: "Stable Audio Open Small",
                                subtitle: "stabilityai/stable-audio-open-small on Hugging Face",
                                urlString: "https://huggingface.co/stabilityai/stable-audio-open-small"
                            )

                            LinkRow(
                                title: "Magenta Realtime",
                                subtitle: "google/magenta-realtime on Hugging Face (duplicate to self-host)",
                                urlString: "https://huggingface.co/google/magenta-realtime"
                            )
                        }
                        .foregroundColor(.white)
                    }
                    .groupBoxStyle(.landingCard)

                    // Tips / known behavior
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Jam tips")
                                .font(.headline)
                            Text("""
MagentaRT currently operates at **25 fps**. For consistent 4/8-bar chunks, we recommend jamming at **100 BPM** or **120 BPM** right now.
""")
                        }
                        .foregroundColor(.white)
                    }
                    .groupBoxStyle(.landingCard)

                    // Community / contact
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Community")
                                .font(.headline)

                            Button {
                                openURL(URL(string: "https://discord.gg/VECkyXEnAd")!)
                            } label: {
                                HStack {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                    Text("Join the Discord")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                            }

                            Button {
                                openURL(URL(string: "mailto:kev@thecollabagepatch.com")!)
                            } label: {
                                HStack {
                                    Image(systemName: "envelope.fill")
                                    Text("Email kev@thecollabagepatch.com")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                            }
                        }
                        .foregroundColor(.white)
                    }
                    .groupBoxStyle(.landingCard)

                    // Collab note
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Collab note")
                                .font(.headline)
                            Text("""
This project is a research collaboration vibe with **Google + Stability AI + Hugging Face + some dude named Kev**.
Join the Discord or email for more info — we’re iterating fast.
""")
                        }
                        .foregroundColor(.white)
                    }
                    .groupBoxStyle(.landingCard)

                    // Spacer + primary CTA
                    VStack(spacing: 12) {
                        Button {
                            hasSeenLanding = true
                        } label: {
                            Text("Start Jamming")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12).fill(Color.green)
                                )
                        }

                        Toggle(isOn: $hasSeenLanding) {
                            Text("Skip this screen next time")
                                .foregroundColor(.white)
                        }
                        .tint(.green)
                    }
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Little helper row for links
private struct LinkRow: View {
    let title: String
    let subtitle: String
    let urlString: String

    var body: some View {
        Button {
            if let url = URL(string: urlString) { UIApplication.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).bold()
                Text(subtitle).font(.footnote).foregroundColor(.gray)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Card style
fileprivate struct LandingCard: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }
}

fileprivate extension GroupBoxStyle where Self == LandingCard {
    static var landingCard: LandingCard { LandingCard() }
}
