import Foundation

public enum CredentialsError: Error, CustomStringConvertible, Equatable {
    case fileMissing(String)
    case hostMissing(String, file: String)
    case tokenMissing(String, file: String)

    public var description: String {
        switch self {
        case .fileMissing(let p): return "Brak pliku: \(p)"
        case .hostMissing(let h, let f): return "Brak hosta \(h) w \(f)"
        case .tokenMissing(let h, let f): return "Brak tokenu dla \(h) w \(f)"
        }
    }
}

public struct Credentials {
    let glabConfigPath: String
    let jiraTokenPath: String

    public init(
        glabConfigPath: String = (("~/Library/Application Support/glab-cli/config.yml") as NSString).expandingTildeInPath,
        jiraTokenPath: String = (("~/.claude/.secrets/jira-token") as NSString).expandingTildeInPath
    ) {
        self.glabConfigPath = glabConfigPath
        self.jiraTokenPath = jiraTokenPath
    }

    public func jiraToken() throws -> String {
        guard let data = FileManager.default.contents(atPath: jiraTokenPath),
              let raw = String(data: data, encoding: .utf8) else {
            throw CredentialsError.fileMissing(jiraTokenPath)
        }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw CredentialsError.fileMissing(jiraTokenPath) }
        return token
    }

    public func gitlabToken(host: String = "drm-gitlab.redlabs.pl") throws -> String {
        guard let data = FileManager.default.contents(atPath: glabConfigPath),
              let content = String(data: data, encoding: .utf8) else {
            throw CredentialsError.fileMissing(glabConfigPath)
        }
        return try Self.parseToken(host: host, yaml: content, file: glabConfigPath)
    }

    public static func parseToken(host: String, yaml: String, file: String) throws -> String {
        let lines = yaml.components(separatedBy: .newlines)
        var inHost = false
        var hostIndent = -1
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix { $0 == " " }.count

            if !inHost {
                if trimmed == "\(host):" {
                    inHost = true
                    hostIndent = indent
                }
                continue
            }

            if !trimmed.isEmpty && indent <= hostIndent {
                break
            }

            if trimmed.hasPrefix("token:") {
                let value = trimmed.dropFirst("token:".count).trimmingCharacters(in: .whitespaces)
                let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if cleaned.isEmpty {
                    throw CredentialsError.tokenMissing(host, file: file)
                }
                return cleaned
            }
        }

        if inHost {
            throw CredentialsError.tokenMissing(host, file: file)
        }
        throw CredentialsError.hostMissing(host, file: file)
    }
}

extension Credentials: CredentialImporting {
    public func importedGitLabToken() throws -> String { try gitlabToken() }
    public func importedJiraToken() throws -> String { try jiraToken() }
}
