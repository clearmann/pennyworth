import Foundation

/// A safe arithmetic evaluator built on Foundation's `Decimal`.
///
/// Grammar:
///
///     expression := term (('+' | '-') term)*
///     term       := unary (('*' | '/') unary)*
///     unary      := ('+' | '-') unary | primary
///     primary    := number | '(' expression ')'
///
/// Numbers are plain decimals (ASCII digits, at most one `.`). Scientific
/// notation is rejected so a query never silently means something different
/// from what the user typed.
///
/// Output rules:
/// - Exact results print without trailing zeros (`1.50` → `1.5`).
/// - If any step lost precision, the final value is rounded to 16 significant
///   digits, halves away from zero.
/// - Negative zero prints as `0`.
enum Calculator {
    static let maxInputLength = 512
    static let maxNestingDepth = 32
    /// `Decimal` stores at most 38 significant digits.
    static let maxSignificantDigits = 38
    /// Digits kept when a result cannot be represented exactly.
    static let outputSignificantDigits = 16

    static func evaluate(_ expression: String) throws -> String {
        guard expression.count <= maxInputLength else {
            throw CalculatorError.expressionTooLong(max: maxInputLength)
        }
        var parser = Parser(tokens: try Tokenizer.tokenize(expression))
        return try Formatter.string(for: parser.parse())
    }
}

// MARK: - Errors

enum CalculatorError: LocalizedError, Equatable {
    case emptyExpression
    case incompleteExpression
    case missingClosingParenthesis
    case expressionTooLong(max: Int)
    case nestingTooDeep(max: Int)
    case unexpectedCharacter(Character)
    case unexpectedToken(String)
    case invalidNumber(String)
    case numberTooPrecise(String)
    case numberOutOfRange(String)
    case divisionByZero
    case overflow
    case underflow

    var errorDescription: String? {
        switch self {
        case .emptyExpression: return "表达式不能为空"
        case .incompleteExpression: return "表达式不完整"
        case .missingClosingParenthesis: return "缺少右括号"
        case .expressionTooLong(let max): return "表达式过长（最多 \(max) 个字符）"
        case .nestingTooDeep(let max): return "嵌套层数过多（最多 \(max) 层）"
        case .unexpectedCharacter(let character): return "包含无法识别的字符：\(character)"
        case .unexpectedToken(let token): return "表达式格式错误：意外的\(token)"
        case .invalidNumber(let text): return "无效的数字：\(text)"
        case .numberTooPrecise(let text):
            return "数字精度超出限制（最多 \(Calculator.maxSignificantDigits) 位有效数字）：\(text)"
        case .numberOutOfRange(let text): return "数字超出可表示范围：\(text)"
        case .divisionByZero: return "除数不能为零"
        case .overflow: return "计算结果溢出"
        case .underflow: return "计算结果下溢（数值过小）"
        }
    }
}

// MARK: - Tokens

private enum Token: Equatable {
    case number(Decimal)
    case plus, minus, star, slash, leftParen, rightParen
}

private enum Tokenizer {
    static func tokenize(_ expression: String) throws -> [Token] {
        let characters = Array(expression)
        var tokens: [Token] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }

            switch character {
            case "+": tokens.append(.plus); index += 1
            case "-": tokens.append(.minus); index += 1
            case "*": tokens.append(.star); index += 1
            case "/": tokens.append(.slash); index += 1
            case "(": tokens.append(.leftParen); index += 1
            case ")": tokens.append(.rightParen); index += 1
            default:
                guard character.isASCII, character.isNumber || character == "." else {
                    throw CalculatorError.unexpectedCharacter(character)
                }
                var text = ""
                while index < characters.count {
                    let next = characters[index]
                    guard next.isASCII, next.isNumber || next == "." else { break }
                    text.append(next)
                    index += 1
                }
                tokens.append(.number(try parseNumber(text)))
            }
        }

        guard !tokens.isEmpty else { throw CalculatorError.emptyExpression }
        return tokens
    }

    private static func parseNumber(_ text: String) throws -> Decimal {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2 else { throw CalculatorError.invalidNumber(text) }

        let digits = pieces.joined()
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw CalculatorError.invalidNumber(text)
        }

        // `Decimal(string:)` silently rounds past 38 digits, so reject those
        // before parsing.
        let significant = digits.drop(while: { $0 == "0" }).reversed().drop(while: { $0 == "0" })
        guard significant.count <= Calculator.maxSignificantDigits else {
            throw CalculatorError.numberTooPrecise(text)
        }

        guard let value = Decimal(string: text, locale: nil), value.isFinite else {
            throw CalculatorError.numberOutOfRange(text)
        }
        return value
    }
}

// MARK: - Values

/// A computed value plus whether any step lost precision.
private struct ComputedValue {
    let decimal: Decimal
    let isInexact: Bool
}

private struct DecimalShape {
    let digits: Int
    let exponent: Int

    var order: Int { digits - 1 + exponent }
}

private func decimalShape(of value: Decimal) -> DecimalShape? {
    guard value.isFinite, !value.isZero else { return nil }
    let digits = value.significand.description.reduce(0) { $1.isNumber ? $0 + 1 : $0 }
    guard digits > 0 else { return nil }
    return DecimalShape(digits: digits, exponent: value.exponent)
}

private func isRecoverable(_ error: Decimal.CalculationError) -> Bool {
    switch error {
    case .noError, .lossOfPrecision: return true
    default: return false
    }
}

// MARK: - Parsing

private struct Parser {
    private let tokens: [Token]
    private var index = 0
    private var depth = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    mutating func parse() throws -> ComputedValue {
        let value = try expression()
        if let token = peek() {
            throw CalculatorError.unexpectedToken(Self.describe(token))
        }
        return value
    }

    private mutating func expression() throws -> ComputedValue {
        var value = try term()
        while let token = peek() {
            if token == .plus {
                index += 1
                value = try DecimalMath.add(value, try term())
            } else if token == .minus {
                index += 1
                value = try DecimalMath.subtract(value, try term())
            } else {
                return value
            }
        }
        return value
    }

    private mutating func term() throws -> ComputedValue {
        var value = try unary()
        while let token = peek() {
            if token == .star {
                index += 1
                value = try DecimalMath.multiply(value, try unary())
            } else if token == .slash {
                index += 1
                value = try DecimalMath.divide(value, try unary())
            } else {
                return value
            }
        }
        return value
    }

    private mutating func unary() throws -> ComputedValue {
        if peek() == .plus {
            index += 1
            try enterNesting()
            defer { depth -= 1 }
            return try unary()
        }
        if peek() == .minus {
            index += 1
            try enterNesting()
            defer { depth -= 1 }
            return DecimalMath.negate(try unary())
        }
        return try primary()
    }

    private mutating func primary() throws -> ComputedValue {
        guard let token = peek() else { throw CalculatorError.incompleteExpression }

        switch token {
        case .number(let decimal):
            index += 1
            return ComputedValue(decimal: decimal, isInexact: false)
        case .leftParen:
            index += 1
            try enterNesting()
            defer { depth -= 1 }
            let value = try expression()
            guard peek() == .rightParen else { throw CalculatorError.missingClosingParenthesis }
            index += 1
            return value
        default:
            throw CalculatorError.unexpectedToken(Self.describe(token))
        }
    }

    private mutating func enterNesting() throws {
        guard depth < Calculator.maxNestingDepth else {
            throw CalculatorError.nestingTooDeep(max: Calculator.maxNestingDepth)
        }
        depth += 1
    }

    private func peek() -> Token? {
        index < tokens.count ? tokens[index] : nil
    }

    private static func describe(_ token: Token) -> String {
        switch token {
        case .number: return "数字"
        case .plus: return "加号"
        case .minus: return "减号"
        case .star: return "乘号"
        case .slash: return "除号"
        case .leftParen: return "左括号"
        case .rightParen: return "右括号"
        }
    }
}

// MARK: - Arithmetic

private enum DecimalMath {
    /// Stored exponents must stay inside this range. Multiply sums operands'
    /// exponents before normalizing and silently corrupts the result when the
    /// sum falls outside it, so multiplication is checked up front.
    static let minExponent = -128
    static let maxExponent = 127

    static func add(_ lhs: ComputedValue, _ rhs: ComputedValue) throws -> ComputedValue {
        try combine(lhs, rhs, subtract: false)
    }

    static func subtract(_ lhs: ComputedValue, _ rhs: ComputedValue) throws -> ComputedValue {
        try combine(lhs, rhs, subtract: true)
    }

    static func negate(_ value: ComputedValue) -> ComputedValue {
        ComputedValue(decimal: -value.decimal, isInexact: value.isInexact)
    }

    static func multiply(_ lhs: ComputedValue, _ rhs: ComputedValue) throws -> ComputedValue {
        guard let left = decimalShape(of: lhs.decimal),
              let right = decimalShape(of: rhs.decimal)
        else {
            return ComputedValue(decimal: 0, isInexact: lhs.isInexact || rhs.isInexact)
        }

        let exponentSum = left.exponent + right.exponent
        guard exponentSum <= maxExponent else { throw CalculatorError.overflow }
        guard exponentSum >= minExponent else { throw CalculatorError.underflow }

        var a = lhs.decimal
        var b = rhs.decimal
        var result = Decimal()
        let error = NSDecimalMultiply(&result, &a, &b, .plain)
        let rounding = try validate(result: &result, error: error)

        let exact = left.digits + right.digits <= Calculator.maxSignificantDigits && !rounding
        return ComputedValue(decimal: result, isInexact: !exact || lhs.isInexact || rhs.isInexact)
    }

    static func divide(_ lhs: ComputedValue, _ rhs: ComputedValue) throws -> ComputedValue {
        guard decimalShape(of: rhs.decimal) != nil else {
            throw CalculatorError.divisionByZero
        }
        guard decimalShape(of: lhs.decimal) != nil else {
            return ComputedValue(decimal: 0, isInexact: lhs.isInexact || rhs.isInexact)
        }

        var a = lhs.decimal
        var b = rhs.decimal
        var result = Decimal()
        let error = NSDecimalDivide(&result, &a, &b, .plain)
        let rounding = try validate(result: &result, error: error)

        let exact = isExactQuotient(result, multiplier: rhs.decimal, dividend: lhs.decimal)
        return ComputedValue(decimal: result, isInexact: !exact || rounding || lhs.isInexact || rhs.isInexact)
    }

    private static func combine(
        _ lhs: ComputedValue,
        _ rhs: ComputedValue,
        subtract: Bool
    ) throws -> ComputedValue {
        var a = lhs.decimal
        var b = rhs.decimal
        var result = Decimal()
        let error = subtract
            ? NSDecimalSubtract(&result, &a, &b, .plain)
            : NSDecimalAdd(&result, &a, &b, .plain)
        let rounding = try validate(result: &result, error: error)

        let exact = decimalSpan(lhs.decimal, rhs.decimal) <= Calculator.maxSignificantDigits && !rounding
        return ComputedValue(decimal: result, isInexact: !exact || lhs.isInexact || rhs.isInexact)
    }

    /// Decimal places the operands span once aligned; more than 38 means the
    /// exact sum does not fit in a `Decimal`.
    private static func decimalSpan(_ lhs: Decimal, _ rhs: Decimal) -> Int {
        guard let left = decimalShape(of: lhs), let right = decimalShape(of: rhs) else { return 1 }
        let highest = max(left.digits + left.exponent, right.digits + right.exponent)
        let lowest = min(left.exponent, right.exponent)
        return highest - lowest
    }

    /// `NSDecimalDivide` reports `.noError` for 1/3, so multiply the quotient
    /// back to decide whether it was exact.
    private static func isExactQuotient(
        _ quotient: Decimal,
        multiplier: Decimal,
        dividend: Decimal
    ) -> Bool {
        var a = quotient
        var b = multiplier
        var product = Decimal()
        let error = NSDecimalMultiply(&product, &a, &b, .plain)
        return isRecoverable(error) && product == dividend
    }

    /// Returns `true` when precision was lost.
    private static func validate(result: inout Decimal, error: Decimal.CalculationError) throws -> Bool {
        switch error {
        case .noError, .lossOfPrecision:
            break
        case .divideByZero:
            throw CalculatorError.divisionByZero
        case .overflow:
            throw CalculatorError.overflow
        case .underflow:
            throw CalculatorError.underflow
        default:
            throw CalculatorError.overflow
        }

        guard result.isFinite else { throw CalculatorError.overflow }
        if let shape = decimalShape(of: result) {
            guard shape.exponent <= maxExponent else { throw CalculatorError.overflow }
            guard shape.exponent >= minExponent else { throw CalculatorError.underflow }
        }

        if case .lossOfPrecision = error { return true }
        return false
    }
}

// MARK: - Formatting

private enum Formatter {
    static func string(for value: ComputedValue) throws -> String {
        guard value.decimal.isFinite else { throw CalculatorError.overflow }

        var decimal = value.decimal
        if value.isInexact {
            decimal = rounded(decimal, to: Calculator.outputSignificantDigits)
        }
        guard decimal.isFinite else { throw CalculatorError.overflow }
        guard !decimal.isZero else { return "0" }
        return decimal.description
    }

    /// Rounds half away from zero: shift the leading digit to the units place,
    /// round to an integer, then shift back. `NSDecimalRound` misbehaves for
    /// scales beyond the value's exponent range, so shifting is explicit.
    private static func rounded(_ value: Decimal, to significantDigits: Int) -> Decimal {
        guard let shape = decimalShape(of: value), shape.digits > significantDigits else {
            return value
        }
        let shift = significantDigits - shape.digits - shape.exponent
        guard shift != 0, abs(shift) <= DecimalMath.maxExponent else { return value }

        var power = Decimal(sign: .plus, exponent: abs(shift), significand: 1)
        var input = value
        var scaled = Decimal()
        let scaleError = shift > 0
            ? NSDecimalMultiply(&scaled, &input, &power, .plain)
            : NSDecimalDivide(&scaled, &input, &power, .plain)
        guard isRecoverable(scaleError) else { return value }

        var whole = Decimal()
        NSDecimalRound(&whole, &scaled, 0, .plain)

        var factor = power
        var restored = Decimal()
        let restoreError = shift > 0
            ? NSDecimalDivide(&restored, &whole, &factor, .plain)
            : NSDecimalMultiply(&restored, &whole, &factor, .plain)
        guard isRecoverable(restoreError) else { return value }
        return restored
    }
}
