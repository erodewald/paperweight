// Formats a String Catalog exactly the way Xcode writes it, so an IDE build
// never rewrites a file this repo's scripts produced. Apple's serializer with
// these three options is byte-identical to Xcode's output: two-space indent,
// `"key" : value`, empty objects on three lines, keys in Unicode collation
// order, no trailing newline.
//
//   swift Scripts/xcstrings-format.swift IN        # in place
//   swift Scripts/xcstrings-format.swift IN OUT
import Foundation

let args = CommandLine.arguments
guard args.count == 2 || args.count == 3 else {
    FileHandle.standardError.write("usage: xcstrings-format.swift IN [OUT]\n".data(using: .utf8)!)
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args.count == 3 ? args[2] : args[1])
do {
    let data = try Data(contentsOf: input)
    let object = try JSONSerialization.jsonObject(with: data)
    let formatted = try JSONSerialization.data(withJSONObject: object,
                                               options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try formatted.write(to: output)
} catch {
    FileHandle.standardError.write("xcstrings-format: \(error)\n".data(using: .utf8)!)
    exit(1)
}
