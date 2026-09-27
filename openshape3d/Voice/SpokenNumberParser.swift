//
//  SpokenNumberParser.swift
//  openshape3d
//
//  PrintCAD V1.2: pulls the numbers out of a transcript ("seven MM hole",
//  "2.5 millimetres", "M3", "twenty five mm deep"). Jev cannot produce numbers
//  — it only chooses between options — so the app finds them here and then asks
//  Jev what each one MEANS (diameter, depth, …). Values are in millimetres.
//

import Foundation

struct SpokenNumber: Equatable {
    /// Millimetres for lengths (cm is converted); plain value otherwise.
    let value: Double
    enum Unit: Equatable { case millimetre, degree, percent, none }
    let unit: Unit
    /// "M3" style fastener size: `value` is the nominal diameter.
    let isFastenerSize: Bool

    /// How the number is shown to the classifier and in the panel.
    var phrase: String {
        let number = Self.format(value)
        if isFastenerSize { return "M\(number) (fastener size)" }
        switch unit {
        case .millimetre: return "\(number) mm"
        case .degree: return "\(number)°"
        case .percent: return "\(number)%"
        case .none: return number
        }
    }

    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }
}

enum SpokenNumberParser {
    static func numbers(in transcript: String) -> [SpokenNumber] {
        let tokens = tokenize(transcript)
        var result: [SpokenNumber] = []
        var i = 0
        while i < tokens.count {
            let token = tokens[i]

            // "M3" / "m 3" — fastener sizes.
            if let size = fastenerSize(token) {
                result.append(SpokenNumber(value: size, unit: .millimetre, isFastenerSize: true))
                i += 1
                continue
            }
            if token == "m", i + 1 < tokens.count, let size = Double(tokens[i + 1]) {
                result.append(SpokenNumber(value: size, unit: .millimetre, isFastenerSize: true))
                i += 2
                continue
            }

            guard let (value, used) = number(at: i, in: tokens) else {
                i += 1
                continue
            }
            var next = i + used
            var unit = SpokenNumber.Unit.none
            var scaled = value
            if next < tokens.count, let (u, factor) = Self.unit(tokens[next]) {
                unit = u
                scaled = value * factor
                next += 1
            }
            result.append(SpokenNumber(value: scaled, unit: unit, isFastenerSize: false))
            i = next
        }
        return result
    }

    // MARK: - Tokens

    /// Lowercased words and numbers; "5mm" → "5", "mm"; "2.5" stays whole.
    private static func tokenize(_ text: String) -> [String] {
        let pattern = #"m\d+(?:\.\d+)?|\d+(?:\.\d+)?|[a-z]+|%"#
        let lower = text.lowercased()
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(lower.startIndex..., in: lower)
        return regex.matches(in: lower, range: range).compactMap {
            Range($0.range, in: lower).map { String(lower[$0]) }
        }
    }

    private static func fastenerSize(_ token: String) -> Double? {
        guard token.hasPrefix("m"), token.count > 1 else { return nil }
        return Double(token.dropFirst())
    }

    private static func unit(_ token: String) -> (SpokenNumber.Unit, Double)? {
        switch token {
        case "mm", "millimeter", "millimeters", "millimetre", "millimetres", "mil", "mils":
            return (.millimetre, 1)
        case "cm", "centimeter", "centimeters", "centimetre", "centimetres":
            return (.millimetre, 10)
        case "degree", "degrees", "deg":
            return (.degree, 1)
        case "%", "percent", "per":
            return (.percent, 1)
        default:
            return nil
        }
    }

    // MARK: - Numbers (digits or words)

    private static let units: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Double] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// A number starting at `index` and how many tokens it used.
    private static func number(at index: Int, in tokens: [String]) -> (Double, Int)? {
        let token = tokens[index]
        if let digits = Double(token) {
            return (digits, 1)
        }
        guard let (whole, used) = wordNumber(at: index, in: tokens) else { return nil }
        var total = whole
        var count = used
        // "two point five", "one point two five"
        if index + count + 1 < tokens.count, tokens[index + count] == "point" {
            var fraction = ""
            var j = index + count + 1
            while j < tokens.count, let digit = units[tokens[j]], digit < 10 {
                fraction += String(Int(digit))
                j += 1
            }
            if !fraction.isEmpty, let value = Double("0.\(fraction)") {
                total += value
                count = j - index
            }
        }
        // "one" alone is usually "this one", not a size: keep it only when a
        // unit or "point" makes it a measurement.
        if token == "one", count == 1 {
            let next = index + 1 < tokens.count ? tokens[index + 1] : ""
            guard unit(next) != nil else { return nil }
        }
        return (total, count)
    }

    private static func wordNumber(at index: Int, in tokens: [String]) -> (Double, Int)? {
        var value: Double = 0
        var used = 0
        var i = index
        if i < tokens.count, let t = tens[tokens[i]] {
            value = t
            used += 1
            i += 1
            if i < tokens.count, let u = units[tokens[i]], u < 10 {
                value += u
                used += 1
                i += 1
            }
        } else if i < tokens.count, let u = units[tokens[i]] {
            value = u
            used += 1
            i += 1
        } else {
            return nil
        }
        if i < tokens.count, tokens[i] == "hundred" {
            value *= 100
            used += 1
            i += 1
            if i < tokens.count, tokens[i] == "and" { i += 1 }
            if let (rest, restUsed) = wordNumber(at: i, in: tokens) {
                value += rest
                used = i - index + restUsed
            }
        }
        return (value, used)
    }
}
