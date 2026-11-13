import Darwin
import Foundation

let root = URL(
    fileURLWithPath: "/Users/develodom/Hacking/Watchface-experiments",
    isDirectory: true
)
let executable = root.appendingPathComponent("tools/ipsw-local/bin/ipsw")
let firmwareRoot = root.appendingPathComponent("Firmware/iPhone19,2", isDirectory: true)
let builds = ["24B5084k", "24B5089g", "24B5099f", "24B5110a", "24B115"]

for build in builds {
    let output = firmwareRoot.appendingPathComponent(build, isDirectory: true)
    try FileManager.default.createDirectory(
        at: output,
        withIntermediateDirectories: true
    )

    let process = Process()
    process.executableURL = executable
    process.currentDirectoryURL = root
    process.arguments = [
        "download", "ipsw",
        "--device", "iPhone19,2",
        "--build", build,
        "--kernel",
        "--confirm",
        "--output", output.path,
        "--no-color",
    ]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    print("starting build=\(build) output=\(output.path)")
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fputs("ipsw failed for \(build): \(process.terminationStatus)\n", stderr)
        exit(process.terminationStatus)
    }
}

print("kernel extraction complete")
