import SwiftUI
import MenuBarCore

struct SettingsView: View {
    @State private var config: AppConfig
    @State private var launchAtLogin: Bool
    private let onSave: (AppConfig) -> Void
    private let setLaunchAtLogin: (Bool) -> Void

    init(
        config: AppConfig,
        launchAtLogin: Bool,
        onSave: @escaping (AppConfig) -> Void,
        setLaunchAtLogin: @escaping (Bool) -> Void
    ) {
        _config = State(initialValue: config)
        _launchAtLogin = State(initialValue: launchAtLogin)
        self.onSave = onSave
        self.setLaunchAtLogin = setLaunchAtLogin
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                launchAtLogin = newValue
                setLaunchAtLogin(newValue)
            }
        )
    }

    private func counterToggle(_ counter: StatusCounter) -> Binding<Bool> {
        Binding(
            get: { config.enabledCounters.contains(counter) },
            set: { isOn in
                if isOn { config.enabledCounters.insert(counter) }
                else { config.enabledCounters.remove(counter) }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ustawienia").font(.headline)

            GroupBox("Ogólne") {
                Toggle("Uruchamiaj przy starcie systemu", isOn: launchAtLoginBinding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }

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

            GroupBox("Liczniki na pasku") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GitLab").font(.subheadline).foregroundStyle(.secondary)
                    Toggle("Otwarte MR", isOn: counterToggle(.gitlabOpen))
                    Toggle("Gotowe do mergu", isOn: counterToggle(.gitlabReady))

                    Text("GitHub").font(.subheadline).foregroundStyle(.secondary)
                    Toggle("Otwarte PR", isOn: counterToggle(.githubOpen))
                    Toggle("Approved", isOn: counterToggle(.githubApproved))

                    Text("Jira").font(.subheadline).foregroundStyle(.secondary)
                    Toggle("Backlog", isOn: counterToggle(.jiraBacklog))
                    Toggle("W toku", isOn: counterToggle(.jiraInProgress))
                    Toggle("W testach — czeka", isOn: counterToggle(.jiraTestingAwaiting))
                    Toggle("Zaakceptowane", isOn: counterToggle(.jiraTestingAccepted))
                    Toggle("Odrzucone", isOn: counterToggle(.jiraTestingRejected))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
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
