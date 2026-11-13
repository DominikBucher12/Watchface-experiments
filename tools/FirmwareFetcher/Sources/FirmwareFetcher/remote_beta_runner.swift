import Darwin
import Foundation

let root = URL(
    fileURLWithPath: "/Users/develodom/Hacking/Watchface-experiments",
    isDirectory: true
)
let executable = root.appendingPathComponent("tools/ipsw-local/bin/ipsw")
let firmwareRoot = root.appendingPathComponent("Firmware/iPhone19,2", isDirectory: true)
let builds = [
    (
        "24B5084k",
        "https://updates.cdn-apple.com/2026FallSeed/c0cbd61b-11c6-4754-b1f4-75932a3fb75d/iPhone19,2,iPhone19,3,iPhone19,7_27.2_24B5084k_Restore.ipsw"
    ),
    (
        "24B5089g",
        "https://updates.cdn-apple.com/2026FallSeed/00a5aa52-71c8-4bd5-9dde-40928b9bc46f/iPhone19,2,iPhone19,3,iPhone19,7_27.2_24B5089g_Restore.ipsw"
    ),
    (
        "24B5099f",
        "https://updates.cdn-apple.com/2026FallSeed/60fdd536-09f2-4449-aeaf-389c8edfb331/iPhone19,2,iPhone19,3,iPhone19,7_27.2_24B5099f_Restore.ipsw"
    ),
    (
        "24B5110a",
        "https://updates.cdn-apple.com/2026FallSeed/60374cb9-211c-4e34-b8df-44d7c7d4f63a/iPhone19,2,iPhone19,3,iPhone19,7_27.2_24B5110a_Restore.ipsw"
    ),
    (
        "24B115",
        "https://updates.cdn-apple.com/2026FallFCS/b5a9eb92-1b03-4d0b-a524-b10c0ce5416e/iPhone19,2,iPhone19,3,iPhone19,7_27.2_24B115_Restore.ipsw"
    ),
]

for (build, url) in builds {
    let output = firmwareRoot.appendingPathComponent(build, isDirectory: true)
    try FileManager.default.createDirectory(
        at: output,
        withIntermediateDirectories: true
    )

    let process = Process()
    process.executableURL = executable
    process.currentDirectoryURL = root
    process.arguments = [
        "extract",
        "--kernel",
        "--remote",
        "--device", "iPhone19,2",
        "--output", output.path,
        "--no-color",
        url,
    ]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    print("starting remote build=\(build) output=\(output.path)")
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fputs("ipsw failed for \(build): \(process.terminationStatus)\n", stderr)
        exit(process.terminationStatus)
    }
}

print("remote beta kernel extraction complete")
