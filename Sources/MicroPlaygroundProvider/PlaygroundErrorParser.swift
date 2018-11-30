import Basic
import Utility
import Foundation

struct PlaygroundError: Codable {
    let location: CodeLocation
    let description: String
}

struct CodeLocation: Codable {
    let row: Int
    let column: Int
}

class PlaygroundErrorParser {

    private var name: String
    var offset: Int

    init(rowOffset: Int = 0, executableName: String) {
        offset = rowOffset
        name = executableName
    }

    func parse(input: String) throws -> [PlaygroundError] {
        var items = [PlaygroundError]()
        let swiftErrorPattern = ".*.swift:((\\d+?)\\:(\\d+?))\\: (error)\\: (.*)\\n(.*)\\n(.*)"
        let results = try RegEx(pattern: swiftErrorPattern).matchGroups(in: input)
        for result in results {
            guard let row = Int(result[1]), let column = Int(result[2]) else { continue }
            let description: String
            if result.count > 6 {
                description = "\(name):\(row):\(column) error: \(result[4])\n\(result[5])\n\(result[6])\n"
            } else {
                description = "\(name):\(row):\(column) error: \(result[4])\n"
            }
            items += [PlaygroundError(location: CodeLocation(row: row + offset, column: column),
                                      description: description)]
        }
        return items
    }

}
