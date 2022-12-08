#!/usr/bin/env xcrun swift

import Foundation

extension String {
    var isEmptyOrWhitespace: Bool {
        return isEmpty || trimmingCharacters(in: .whitespaces) == ""
    }

    var isNotEmptyOrWhitespace: Bool {
        return !isEmptyOrWhitespace
    }
}

// MARK: - Parser - https://github.com/Daniel1of1/CSwiftV/blob/develop/Sources/CSwiftV/CSwiftV.swift

public class CSwiftV {

    /// The number of columns in the data
    private let columnCount: Int
    /// The headers from the data, an Array of String
    public let headers: [String]
    /// An array of Dictionaries with the values of each row keyed to the header
    public let keyedRows: [[String: String]]
    /// An Array of the rows in an Array of String form, equivalent to keyedRows, but without the keys
    public let rows: [[String]]
    
    /// Creates an instance containing the data extracted from the `with` String
    /// - Parameter with: The String obtained from reading the csv file.
    /// - Parameter separator: The separator used in the csv file, defaults to ","
    /// - Parameter headers: The array of headers from the file. If not included, it will be populated with the ones from the first line
    public init(with string: String, separator: String = ",", headers: [String]? = nil) {
        var parsedLines = CSwiftV.records(from: string.replacingOccurrences(of: "\r\n", with: "\n")).map { CSwiftV.cells(forRow: $0, separator: separator) }
        self.headers = headers ?? parsedLines.removeFirst()
        rows = parsedLines
        columnCount = self.headers.count

        let tempHeaders = self.headers
        keyedRows = rows.map { field -> [String: String] in
            var row = [String: String]()
            // Only store value which are not empty
            for (index, value) in field.enumerated() where value.isNotEmptyOrWhitespace {
                if index < tempHeaders.count {
                    row[tempHeaders[index]] = value
                }
            }
            return row
        }
    }
    
    /// Analizes a row and tries to obtain the different cells contained as an Array of String
    /// - Parameter forRow: The string corresponding to a row of the data matrix
    /// - Parameter separator: The string that delimites the cells or fields inside the row. Defaults to ","
    internal static func cells(forRow string: String, separator: String = ",") -> [String] {
        return CSwiftV.split(separator, string: string)
    }

    /// Analizes the CSV data as an String, and separates the different rows as an individual String each.
    /// - Parameter forRow: The string corresponding the whole data
    /// - Attention: Assumes "\n" as row delimiter, needs to filter string for "\r\n" first
    internal static func records(from string: String) -> [String] {
        return CSwiftV.split("\n", string: string).filter { $0.isNotEmptyOrWhitespace }
    }

    /// Tries to preserve the parity between open and close characters for different formats. Analizes the escape character count to do so
    private static func split(_ separator: String, string: String) -> [String] {
        func oddNumberOfQuotes(_ string: String) -> Bool {
            return string.components(separatedBy: "\"").count % 2 == 0
        }

        let initial = string.components(separatedBy: separator)
        var merged = [String]()
        for newString in initial {
            guard let record = merged.last , oddNumberOfQuotes(record) == true else {
                merged.append(newString)
                continue
            }
            merged.removeLast()
            let lastElem = record + separator + newString
            merged.append(lastElem)
        }
        return merged
    }
}

// MARK: - Generator
enum GeneratorError: Error {
    case missingNameForEventGroup
    case missingNameForEvent
}

struct EventGroup: Encodable {
    let name: String
    let screen_views: [Event]?
    let events: [Event]?
}

struct Event: Encodable {
    let event_trigger: String
    let name: String
    let content: [EventContent]?
    let parameters: [EventContent]?
}

struct EventContent: Encodable {
    let name: String
    let value: String
}

let paramValues: Set<String> = ["string", "int", "double"]

func makeEventGroup(name: String, keyedRows: [[String: String]]) throws -> EventGroup {
    var screenViews: [Event] = []
    var events: [Event] = []
    
    for keyedRow in keyedRows {
        var row = keyedRow
        guard let name = row["name"] else { throw GeneratorError.missingNameForEvent }
        row["name"] = nil // name should be included in content.
        
        let isScreen = row["event_label"] == nil
        let eventTrigger = isScreen ? "hm_push_screen" : "hm_push_event"
        
        var content: [EventContent] = []
        var parameters: [EventContent] = []
        for (name, value) in row {
            let eventContent = EventContent(name: name, value: value)
            if paramValues.contains(value) {
                parameters.append(eventContent)
            } else {
                content.append(eventContent)
            }
        }
        
        let event = Event(
            event_trigger: eventTrigger,
            name: name,
            content: content.isEmpty ? nil : content,
            parameters: parameters.isEmpty ? nil : parameters
        )
        if isScreen {
            screenViews.append(event)
        } else {
            events.append(event)
        }
    }
    
    return EventGroup(
        name: name,
        screen_views: screenViews.isEmpty ? nil : screenViews,
        events: events.isEmpty ? nil : events
    )
}

// MARK: - Reader

print("Reading started")
var eventGroups: [EventGroup] = []

let directory = "ga"
let allCsvPaths = try FileManager.default.contentsOfDirectory(atPath: directory)
for path in allCsvPaths {
    print("Reading: \(path)")
    let url = URL(fileURLWithPath: "\(directory)/\(path)")
    let csvData = try Data(contentsOf: url)
    let csvStr = String(data: csvData, encoding: .utf8)!
    
    print("Decoding: \(path)")
    let csv = CSwiftV(with: csvStr)
    let keyedRows = csv.keyedRows
    let name = path.replacingOccurrences(of: ".csv", with: "")
    let eventGroup = try makeEventGroup(name: name, keyedRows: keyedRows)
    eventGroups.append(eventGroup)
}

print("Generating")

let jsonData = try JSONEncoder().encode(eventGroups)
let jsonStr = String(data: jsonData, encoding: .utf8)!
try jsonStr.write(toFile: "analytics.json", atomically: true, encoding: .utf8)
