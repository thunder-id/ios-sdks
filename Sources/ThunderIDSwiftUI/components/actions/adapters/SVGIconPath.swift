/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import SwiftUI

/// Renders a single `<path d="...">` from a brand icon's SVG source, scaled into the given
/// `viewBox`. Supports the M/L/H/V/C/A/Z commands (absolute and relative) used by the
/// Google/GitHub logos ported from the web SDK's icon adapters.
struct SVGIconPath: Shape {
    let pathData: String
    let viewBox: CGSize
    /// Translation applied in the SVG's own coordinate space, matching a `<g transform="translate(...)">`
    /// wrapper around the source `<path>` (e.g. Google's four-color glyph groups).
    var translate: CGSize = .zero

    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / viewBox.width
        let scaleY = rect.height / viewBox.height
        var path = Path()
        func mapped(_ point: CGPoint) -> CGPoint {
            let translated = CGPoint(x: point.x + translate.width, y: point.y + translate.height)
            return CGPoint(x: rect.minX + translated.x * scaleX, y: rect.minY + translated.y * scaleY)
        }
        for segment in SVGPathParser.parse(pathData) {
            segment.apply(to: &path, map: mapped)
        }
        return path
    }
}

/// A parsed drawing instruction in the SVG path's own coordinate space (pre-scaling).
private enum SVGPathSegment {
    case move(CGPoint)
    case line(CGPoint)
    case curve(control1: CGPoint, control2: CGPoint, end: CGPoint)
    case close

    func apply(to path: inout Path, map: (CGPoint) -> CGPoint) {
        switch self {
        case .move(let point):
            path.move(to: map(point))
        case .line(let point):
            path.addLine(to: map(point))
        case .curve(let control1, let control2, let end):
            path.addCurve(to: map(end), control1: map(control1), control2: map(control2))
        case .close:
            path.closeSubpath()
        }
    }
}

/// Minimal SVG path-data ("d" attribute) parser producing `SVGPathSegment`s.
private enum SVGPathParser {
    static func parse(_ data: String) -> [SVGPathSegment] {
        let chars = Array(data)
        var idx = 0
        var segments: [SVGPathSegment] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var command: Character = "M"

        while idx < chars.count {
            skipSeparators(chars, &idx)
            guard idx < chars.count else { break }
            if chars[idx].isLetter {
                command = chars[idx]
                idx += 1
            } else if command == "M" {
                command = "L"
            } else if command == "m" {
                command = "l"
            }
            guard let numbers = readNumbers(for: command, chars, &idx) else { continue }
            apply(command, numbers, &current, &subpathStart, &segments)
        }
        return segments
    }

    private static func readNumbers(for command: Character, _ chars: [Character], _ idx: inout Int) -> [Double]? {
        let count = argumentCount(for: command)
        guard count > 0 else { return [] }
        var values: [Double] = []
        for _ in 0..<count {
            guard let value = parseNumber(chars, &idx) else { return values.isEmpty ? nil : values }
            values.append(value)
        }
        return values
    }

    private static func argumentCount(for command: Character) -> Int {
        switch command.lowercased() {
        case "m", "l", "t": return 2
        case "h", "v": return 1
        case "c": return 6
        case "s", "q": return 4
        case "a": return 7
        case "z": return 0
        default: return 0
        }
    }

    private static func apply(
        _ command: Character,
        _ values: [Double],
        _ current: inout CGPoint,
        _ subpathStart: inout CGPoint,
        _ segments: inout [SVGPathSegment]
    ) {
        let isRelative = command.isLowercase
        func resolved(_ deltaX: Double, _ deltaY: Double) -> CGPoint {
            isRelative ? CGPoint(x: current.x + deltaX, y: current.y + deltaY) : CGPoint(x: deltaX, y: deltaY)
        }
        switch command.lowercased() {
        case "m":
            let point = resolved(values[0], values[1])
            segments.append(.move(point))
            current = point
            subpathStart = point
        case "l":
            let point = resolved(values[0], values[1])
            segments.append(.line(point))
            current = point
        case "h":
            let point = CGPoint(x: isRelative ? current.x + values[0] : values[0], y: current.y)
            segments.append(.line(point))
            current = point
        case "v":
            let point = CGPoint(x: current.x, y: isRelative ? current.y + values[0] : values[0])
            segments.append(.line(point))
            current = point
        case "c":
            let control1 = resolved(values[0], values[1])
            let control2 = resolved(values[2], values[3])
            let end = resolved(values[4], values[5])
            segments.append(.curve(control1: control1, control2: control2, end: end))
            current = end
        case "a":
            let end = resolved(values[5], values[6])
            let arc = EllipticalArc(
                start: current,
                end: end,
                radiusX: values[0],
                radiusY: values[1],
                rotationDegrees: values[2],
                largeArc: values[3] != 0,
                sweep: values[4] != 0
            )
            segments.append(contentsOf: arc.bezierSegments())
            current = end
        case "z":
            segments.append(.close)
            current = subpathStart
        default:
            break
        }
    }

    private static func skipSeparators(_ chars: [Character], _ idx: inout Int) {
        while idx < chars.count, chars[idx] == "," || chars[idx].isWhitespace {
            idx += 1
        }
    }

    private static func parseNumber(_ chars: [Character], _ idx: inout Int) -> Double? {
        skipSeparators(chars, &idx)
        guard idx < chars.count else { return nil }
        var str = ""
        if chars[idx] == "-" || chars[idx] == "+" {
            str.append(chars[idx])
            idx += 1
        }
        var sawDot = false
        while idx < chars.count, chars[idx].isNumber || (chars[idx] == "." && !sawDot) {
            if chars[idx] == "." { sawDot = true }
            str.append(chars[idx])
            idx += 1
        }
        if idx < chars.count, chars[idx] == "e" || chars[idx] == "E" {
            var expStr = String(chars[idx])
            var lookahead = idx + 1
            if lookahead < chars.count, chars[lookahead] == "+" || chars[lookahead] == "-" {
                expStr.append(chars[lookahead])
                lookahead += 1
            }
            while lookahead < chars.count, chars[lookahead].isNumber {
                expStr.append(chars[lookahead])
                lookahead += 1
            }
            str += expStr
            idx = lookahead
        }
        return Double(str)
    }
}

/// An SVG elliptical arc ("A"/"a" command), convertible to cubic-bezier segments per the
/// SVG 1.1 spec's endpoint-to-center-parameterization (Appendix F.6.5).
private struct EllipticalArc {
    let start: CGPoint
    let end: CGPoint
    let radiusX: Double
    let radiusY: Double
    let rotationDegrees: Double
    let largeArc: Bool
    let sweep: Bool

    /// Center-parameterization values derived from the endpoint form.
    private struct CenterForm {
        let center: CGPoint
        let radiusX: Double
        let radiusY: Double
        let cosRotation: Double
        let sinRotation: Double
        let startAngle: Double
        let sweepAngle: Double
    }

    func bezierSegments() -> [SVGPathSegment] {
        guard radiusX != 0, radiusY != 0, start != end, let form = centerForm() else {
            return [.line(end)]
        }
        let segmentCount = max(1, Int(ceil(abs(form.sweepAngle) / (.pi / 2))))
        let step = form.sweepAngle / Double(segmentCount)
        var angle = form.startAngle
        var segments: [SVGPathSegment] = []
        for _ in 0..<segmentCount {
            let nextAngle = angle + step
            segments.append(bezierSegment(from: angle, to: nextAngle, form: form))
            angle = nextAngle
        }
        return segments
    }

    private func centerForm() -> CenterForm? {
        var radiusX = abs(self.radiusX)
        var radiusY = abs(self.radiusY)
        let rotation = rotationDegrees * .pi / 180
        let cosRotation = cos(rotation)
        let sinRotation = sin(rotation)
        let halfDeltaX = Double(start.x - end.x) / 2
        let halfDeltaY = Double(start.y - end.y) / 2
        let rotatedX = cosRotation * halfDeltaX + sinRotation * halfDeltaY
        let rotatedY = -sinRotation * halfDeltaX + cosRotation * halfDeltaY

        let scaleCheck = (rotatedX * rotatedX) / (radiusX * radiusX) + (rotatedY * rotatedY) / (radiusY * radiusY)
        if scaleCheck > 1 {
            let scale = sqrt(scaleCheck)
            radiusX *= scale
            radiusY *= scale
        }

        let sign: Double = largeArc != sweep ? 1 : -1
        let numerator = radiusX * radiusX * radiusY * radiusY
            - radiusX * radiusX * rotatedY * rotatedY
            - radiusY * radiusY * rotatedX * rotatedX
        let denominator = radiusX * radiusX * rotatedY * rotatedY + radiusY * radiusY * rotatedX * rotatedX
        let coefficient = denominator == 0 ? 0 : sign * sqrt(max(0, numerator / denominator))
        let centerRotatedX = coefficient * (radiusX * rotatedY) / radiusY
        let centerRotatedY = coefficient * -(radiusY * rotatedX) / radiusX

        let centerX = cosRotation * centerRotatedX - sinRotation * centerRotatedY + Double(start.x + end.x) / 2
        let centerY = sinRotation * centerRotatedX + cosRotation * centerRotatedY + Double(start.y + end.y) / 2

        let startVectorX = (rotatedX - centerRotatedX) / radiusX
        let startVectorY = (rotatedY - centerRotatedY) / radiusY
        let endVectorX = (-rotatedX - centerRotatedX) / radiusX
        let endVectorY = (-rotatedY - centerRotatedY) / radiusY
        let startAngle = Self.angleBetween(1, 0, startVectorX, startVectorY)
        var sweepAngle = Self.angleBetween(startVectorX, startVectorY, endVectorX, endVectorY)
        if !sweep, sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep, sweepAngle < 0 { sweepAngle += 2 * .pi }

        return CenterForm(
            center: CGPoint(x: centerX, y: centerY),
            radiusX: radiusX,
            radiusY: radiusY,
            cosRotation: cosRotation,
            sinRotation: sinRotation,
            startAngle: startAngle,
            sweepAngle: sweepAngle
        )
    }

    private func bezierSegment(from angle: Double, to nextAngle: Double, form: CenterForm) -> SVGPathSegment {
        let kappa = 4.0 / 3.0 * tan((nextAngle - angle) / 4.0)
        let cosStart = cos(angle), sinStart = sin(angle)
        let cosEnd = cos(nextAngle), sinEnd = sin(nextAngle)
        let control1 = mapUnitPoint(cosStart - kappa * sinStart, sinStart + kappa * cosStart, form: form)
        let control2 = mapUnitPoint(cosEnd + kappa * sinEnd, sinEnd - kappa * cosEnd, form: form)
        let segmentEnd = mapUnitPoint(cosEnd, sinEnd, form: form)
        return .curve(control1: control1, control2: control2, end: segmentEnd)
    }

    private func mapUnitPoint(_ unitX: Double, _ unitY: Double, form: CenterForm) -> CGPoint {
        let scaledX = form.radiusX * unitX
        let scaledY = form.radiusY * unitY
        return CGPoint(
            x: form.cosRotation * scaledX - form.sinRotation * scaledY + form.center.x,
            y: form.sinRotation * scaledX + form.cosRotation * scaledY + form.center.y
        )
    }

    private static func angleBetween(_ fromX: Double, _ fromY: Double, _ toX: Double, _ toY: Double) -> Double {
        let dot = fromX * toX + fromY * toY
        let magnitude = sqrt((fromX * fromX + fromY * fromY) * (toX * toX + toY * toY))
        var angle = acos(max(-1, min(1, dot / magnitude)))
        if fromX * toY - fromY * toX < 0 { angle = -angle }
        return angle
    }
}
