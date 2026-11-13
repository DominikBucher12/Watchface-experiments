import CryptoKit
import Foundation

struct Release: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    let assets: [Asset]
}

enum FetchError: Error, CustomStringConvertible {
    case badStatus(URL, Int)
    case missingAsset(String)
    case checksumMissing(String)
    case checksumMismatch(expected: String, actual: String)

    var description: String {
        switch self {
        case let .badStatus(url, status):
            return "HTTP \(status) for \(url)"
        case let .missingAsset(name):
            return "release asset not found: \(name)"
        case let .checksumMissing(name):
            return "checksum not found for \(name)"
        case let .checksumMismatch(expected, actual):
            return "SHA-256 mismatch: expected \(expected), got \(actual)"
        }
    }
}

func fetch(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue("WatchFaceLab-CVE-research", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200...299).contains(status) else {
        throw FetchError.badStatus(url, status)
    }
    return data
}

let version = "3.1.745"
let wanted = "ipsw_\(version)_macOS_arm64.tar.gz"
let releaseURL = URL(
    string: "https://api.github.com/repos/blacktop/ipsw/releases/tags/v\(version)"
)!
let destination = URL(
    fileURLWithPath: "/Users/develodom/Hacking/Watchface-experiments/tools/ipsw-local"
)

let release = try JSONDecoder().decode(
    Release.self,
    from: try await fetch(releaseURL)
)
guard let archive = release.assets.first(where: { $0.name == wanted }) else {
    throw FetchError.missingAsset(wanted)
}
guard let checksums = release.assets.first(where: { $0.name == "checksums.txt" }) else {
    throw FetchError.missingAsset("checksums.txt")
}

let archiveData = try await fetch(archive.browser_download_url)
let checksumData = try await fetch(checksums.browser_download_url)
try FileManager.default.createDirectory(
    at: destination,
    withIntermediateDirectories: true
)

let archiveURL = destination.appendingPathComponent(wanted)
let checksumURL = destination.appendingPathComponent("checksums.txt")
try archiveData.write(to: archiveURL, options: .atomic)
try checksumData.write(to: checksumURL, options: .atomic)

let checksumText = String(decoding: checksumData, as: UTF8.self)
guard let line = checksumText.split(separator: "\n").first(where: {
    $0.hasSuffix("  \(wanted)") || $0.hasSuffix(" *\(wanted)")
}), let expected = line.split(separator: " ").first else {
    throw FetchError.checksumMissing(wanted)
}
let digest = SHA256.hash(data: archiveData)
let actual = digest.map { String(format: "%02x", $0) }.joined()
guard actual == expected else {
    throw FetchError.checksumMismatch(
        expected: String(expected),
        actual: actual
    )
}

print("downloaded=\(archiveURL.path)")
print("bytes=\(archiveData.count)")
print("sha256=\(actual)")
