import SwiftUI
import MenuBarCore

struct SettingsView: View {
    @State private var config: AppConfig
    private let onSave: (AppConfig) -> Void

    init(config: AppConfig, onSave: @escaping (AppConfig) -> Void) {
        _config = State(initialValue: config)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ustawienia").font(.headline)

            GroupBox("GitLab") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Włącz GitLab", isOn: $config.gitlabEnabled)
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Host") { TextField("", text: $config.gitlabHost) }
                        LabeledContent("Token") { SecureField("PRIVATE-TOKEN", text: $config.gitlabToken) }
                    }
                    .disabled(!config.gitlabEnabled)
                }.padding(6)
            }

            GroupBox("Jira") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Host") { TextField("", text: $config.jiraHost) }
                    LabeledContent("Token") { SecureField("Bearer PAT", text: $config.jiraToken) }
                }.padding(6)
            }

            GroupBox("GitHub") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Włącz GitHub", isOn: $config.githubEnabled)
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Host") { TextField("api.github.com", text: $config.githubHost) }
                        LabeledContent("Token") { SecureField("Personal Access Token", text: $config.githubToken) }
                    }
                    .disabled(!config.githubEnabled)
                }.padding(6)
            }

            HStack {
                Spacer()
                Button("Zapisz") { onSave(config) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!config.hasAnySource)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
