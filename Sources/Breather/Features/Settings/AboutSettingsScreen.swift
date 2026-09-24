import AppKit
import SwiftUI

struct AboutSettingsScreen: View {
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
                    .font(.headline)

                Text(versionDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 16)

            feedbackGroup

            SettingsGroup("支持项目") {
                AboutActionRow(
                    title: "在 GitHub 点星标",
                    systemImage: "star",
                    destination: repositoryURL
                )
            }
        }
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
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String

        guard let version, !version.isEmpty else { return "开发版本" }
        guard let build, !build.isEmpty else { return "版本 \(version)" }
        return "版本 \(version)（构建 \(build)）"
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
