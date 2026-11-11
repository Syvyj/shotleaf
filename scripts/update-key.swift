// The key that signs each release's checksum file, so the app accepts an update only
// from whoever holds it (checked before the disk image is even opened). Ed25519, CryptoKit.
//   swift scripts/update-key.swift new          → private key, then public key (base64, a line each)
//   swift scripts/update-key.swift sign FILE    → the signature of FILE (base64); the private key comes on stdin
//   swift scripts/update-key.swift public       → the public key of the private key on stdin
import CryptoKit
import Foundation

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "new":
    let key = Curve25519.Signing.PrivateKey()
    print(key.rawRepresentation.base64EncodedString())
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(privateKey().publicKey.rawRepresentation.base64EncodedString())
case "sign" where args.count == 2:
    let key = privateKey()
    let file = try Data(contentsOf: URL(fileURLWithPath: args.last!))
    print(try key.signature(for: file).base64EncodedString())
default:
    FileHandle.standardError.write(Data("usage: update-key.swift new | public | sign FILE\n".utf8)); exit(2)
}

func privateKey() -> Curve25519.Signing.PrivateKey {
    let secret = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw = Data(base64Encoded: secret), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        FileHandle.standardError.write(Data("not an update key\n".utf8)); exit(1)
    }
    return key
}
