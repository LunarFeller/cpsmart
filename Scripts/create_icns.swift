import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: create_icns.swift INPUT_ICONSET OUTPUT_ICNS\n", stderr)
    exit(2)
}

let inputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let iconFiles: [(type: String, name: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func appendFourCC(_ value: String, to data: inout Data) {
    precondition(value.utf8.count == 4)
    data.append(contentsOf: value.utf8)
}

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { bytes in
        data.append(contentsOf: bytes)
    }
}

var chunks = Data()
for iconFile in iconFiles {
    let PNG = try Data(contentsOf: inputDirectory.appendingPathComponent(iconFile.name))
    appendFourCC(iconFile.type, to: &chunks)
    appendBigEndian(UInt32(PNG.count + 8), to: &chunks)
    chunks.append(PNG)
}

var ICNS = Data()
appendFourCC("icns", to: &ICNS)
appendBigEndian(UInt32(chunks.count + 8), to: &ICNS)
ICNS.append(chunks)
try ICNS.write(to: outputURL, options: .atomic)
