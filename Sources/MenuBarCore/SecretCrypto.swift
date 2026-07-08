import Foundation
import CryptoKit

enum SecretCryptoError: Error {
    case sealFailed
}

/// Symmetric obfuscation-at-rest for the consolidated credentials blob.
///
/// The key is derived from a static pepper compiled into the binary, so this hides
/// secrets from a casual `security … -w` dump but is NOT a substitute for the
/// Keychain's own protection — anyone with the app binary can reconstruct the key.
enum SecretCrypto {
    private static let key: SymmetricKey = {
        let pepper = "MRJiraMenuBar/v1/credentials-pepper"
        return SymmetricKey(data: Data(SHA256.hash(data: Data(pepper.utf8))))
    }()

    static func seal(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)

        guard let combined = sealed.combined else { throw SecretCryptoError.sealFailed }

        return combined
    }

    static func open(_ combined: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }
}
