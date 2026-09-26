import AppKit
import SwiftUI

struct AboutSettingsScreen: View {
    @ObservedObject var updateMonitor: UpdateMonitor
    @Environment(\.openURL) private var openURL

    private let repositoryURL = URL(string: "https://github.com/M3tar/Breather")!
    private let feedbackURL = URL(
        string: "mailto:1191527614@qq.com?subject=Breather%20%E5%8F%8D%E9%A6%88"
    )!
    private let githubFeedbackURL = URL(
        string: "https://github.com/M3tar/Breather/issues/new"
    )!

    var body: some View {
        SettingsScreenContainer {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    .accessibilityHidden(true)

                Text("Breather")
                    .font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 16)

            versionAndUpdateGroup

            feedbackGroup

            SettingsGroup("支持项目") {
                AboutActionRow(
                    title: "在 GitHub 点星标",
                    systemImage: "star",
                    destination: repositoryURL
                )
            }
        }
        .onAppear {
            Task { await updateMonitor.checkIfDue() }
        }
    }

    private var versionAndUpdateGroup: some View {
        GroupBox {
            VStack(spacing: 0) {
                SettingsRow(title: "版本") {
                    Text(versionDescription)
                        .foregroundStyle(.secondary)
                }

                SettingsDivider()

                SettingsRow(title: "检查更新", description: updateMonitor.status.message) {
                    HStack(spacing: 8) {
                        if updateMonitor.status.isChecking {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("正在检查更新")
                        }

                        Button(updateMonitor.availableUpdate == nil ? "检查更新" : "重新检查") {
                            Task { await updateMonitor.checkNow() }
                        }
                        .disabled(updateMonitor.status.isChecking)

                        if let update = updateMonitor.availableUpdate {
                            Button("前往 GitHub 下载") {
                                openURL(update.releaseURL)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .groupBoxStyle(.automatic)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var feedbackGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("反馈")
                    .font(.headline)
                    .fixedSize()

                Text("谢谢你下载 Breather！发现了 Bug、有特别想要的功能，或者只是想夸夸设计者？都欢迎告诉我。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox {
                VStack(spacing: 0) {
                    AboutActionRow(
                        title: "发送邮件反馈",
                        systemImage: "envelope",
                        destination: feedbackURL
                    )

                    SettingsDivider()

                    AboutActionRow(
                        title: "在 GitHub 提交反馈",
                        systemImage: "bubble.left",
                        destination: githubFeedbackURL
                    )
                }
                .padding(.vertical, 2)
            }
            .groupBoxStyle(.automatic)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var versionDescription: String {
        let version = installedVersion
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String

        guard !version.isEmpty else { return "开发版本" }
        guard let build, !build.isEmpty else { return version }
        return "\(version)（构建 \(build)）"
    }

    private var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

private struct AboutActionRow: View {
    let title: String
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)

                Text(title)

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
