@testable import Pennyworth
import XCTest

final class CalculatorTests: XCTestCase {
    // MARK: - Basic arithmetic

    func testMultiplication() throws {
        XCTAssertEqual(try Calculator.evaluate("23 * 17"), "391")
    }

    func testAdditionAndSubtraction() throws {
        XCTAssertEqual(try Calculator.evaluate("2 + 3"), "5")
        XCTAssertEqual(try Calculator.evaluate("7 - 12"), "-5")
    }

    func testDivisionProducesExactDecimal() throws {
        XCTAssertEqual(try Calculator.evaluate("10 / 4"), "2.5")
        XCTAssertEqual(try Calculator.evaluate("1 / 8"), "0.125")
    }

    func testWhitespaceIsIgnored() throws {
        XCTAssertEqual(try Calculator.evaluate("  1+2*3  "), "7")
        XCTAssertEqual(try Calculator.evaluate("\t( 1 + 2 )\n"), "3")
    }

    // MARK: - Precedence and associativity

    func testMultiplicationBindsTighterThanAddition() throws {
        XCTAssertEqual(try Calculator.evaluate("2 + 3 * 4"), "14")
        XCTAssertEqual(try Calculator.evaluate("2 * 3 + 4"), "10")
        XCTAssertEqual(try Calculator.evaluate("10 - 6 / 3"), "8")
    }

    func testSamePrecedenceIsLeftAssociative() throws {
        XCTAssertEqual(try Calculator.evaluate("8 - 3 - 2"), "3")
        XCTAssertEqual(try Calculator.evaluate("8 / 4 / 2"), "1")
    }

    func testParenthesesOverridePrecedence() throws {
        XCTAssertEqual(try Calculator.evaluate("(2 + 3) * 4"), "20")
        XCTAssertEqual(try Calculator.evaluate("((2 + 3) * (4 - 1)) / 5"), "3")
    }

    // MARK: - Unary signs

    func testUnaryMinus() throws {
        XCTAssertEqual(try Calculator.evaluate("-5"), "-5")
        XCTAssertEqual(try Calculator.evaluate("-(3 + 4)"), "-7")
        XCTAssertEqual(try Calculator.evaluate("3 * -2"), "-6")
    }

    func testUnaryPlusAndStackedSigns() throws {
        XCTAssertEqual(try Calculator.evaluate("+5"), "5")
        XCTAssertEqual(try Calculator.evaluate("--5"), "5")
        XCTAssertEqual(try Calculator.evaluate("-(-(-2))"), "-2")
    }

    // MARK: - Decimal handling

    func testClassicFloatingPointTrapStaysExact() throws {
        XCTAssertEqual(try Calculator.evaluate("0.1 + 0.2"), "0.3")
    }

    func testTrailingZerosAreDropped() throws {
        XCTAssertEqual(try Calculator.evaluate("1.50 + 0"), "1.5")
        XCTAssertEqual(try Calculator.evaluate("2.5 * 2"), "5")
        XCTAssertEqual(try Calculator.evaluate("0.300 + 0"), "0.3")
    }

    func testLeadingAndBareDecimalPoints() throws {
        XCTAssertEqual(try Calculator.evaluate(".5 + .25"), "0.75")
        XCTAssertEqual(try Calculator.evaluate("5. + 1"), "6")
    }

    func testLongIntegersKeepEveryDigit() throws {
        XCTAssertEqual(try Calculator.evaluate("123456789012345678 + 1"), "123456789012345679")
    }

    func testNonTerminatingDivisionRoundsToSixteenSignificantDigits() throws {
        XCTAssertEqual(try Calculator.evaluate("1 / 3"), "0.3333333333333333")
        XCTAssertEqual(try Calculator.evaluate("2 / 3"), "0.6666666666666667")
    }

    func testNegativeZeroPrintsAsZero() throws {
        XCTAssertEqual(try Calculator.evaluate("0 * -1"), "0")
        XCTAssertEqual(try Calculator.evaluate("-0"), "0")
    }

    // MARK: - Invalid input

    func testEmptyAndWhitespaceOnlyExpressionsAreRejected() {
        assertError(.emptyExpression, " ")
        assertError(.emptyExpression, "\n\t")
    }

    func testMalformedExpressionsAreRejected() {
        assertError(.incompleteExpression, "1 +")
        assertError(.unexpectedToken("右括号"), "1 + 2)")
        assertError(.missingClosingParenthesis, "(1 + 2")
        assertError(.incompleteExpression, "(")
    }

    func testNonNumericAndScientificNotationAreRejected() {
        assertError(.unexpectedCharacter("a"), "abc")
        assertError(.unexpectedCharacter("√"), "√4")
        assertError(.unexpectedCharacter("e"), "1e5")
        assertError(.invalidNumber("1..2"), "1..2")
    }

    func testAdjacentNumbersAreRejected() {
        assertError(.unexpectedToken("数字"), "1 2")
    }

    // MARK: - Resource limits

    func testExpressionLengthLimit() throws {
        // Exactly maxInputLength characters: 255 additions plus a trailing space.
        let atLimit = String(repeating: "1+", count: 255) + "1 "
        XCTAssertEqual(atLimit.count, Calculator.maxInputLength)
        XCTAssertEqual(try Calculator.evaluate(atLimit), "256")

        let tooLong = String(repeating: "1+", count: 256) + "1"
        assertError(.expressionTooLong(max: Calculator.maxInputLength), tooLong)
    }

    func testNestingDepthLimit() {
        func nested(_ depth: Int) -> String {
            String(repeating: "(", count: depth) + "1" + String(repeating: ")", count: depth)
        }

        XCTAssertThrowsError(try Calculator.evaluate(nested(Calculator.maxNestingDepth + 1))) { error in
            guard case .nestingTooDeep(let max)? = error as? CalculatorError else {
                return XCTFail("expected nestingTooDeep, got \(error)")
            }
            XCTAssertEqual(max, Calculator.maxNestingDepth)
        }
    }

    func testTooManySignificantDigitsAreRejected() {
        let number = String(repeating: "9", count: Calculator.maxSignificantDigits + 1)
        assertError(.numberTooPrecise(number), number)
    }

    // MARK: - Division by zero and range errors

    func testDivisionByZero() {
        assertError(.divisionByZero, "1 / 0")
        assertError(.divisionByZero, "1 / (2 - 2)")
    }

    func testOverflowIsReported() {
        let huge = "1" + String(repeating: "0", count: 100)
        assertError(.overflow, "\(huge) * \(huge)")
    }

    func testUnderflowIsReported() {
        let tiny = "0." + String(repeating: "0", count: 99) + "1"
        assertError(.underflow, "\(tiny) * \(tiny)")
    }

    // MARK: - Errors

    func testErrorsAreLocalizedInChinese() {
        guard let message = CalculatorError.divisionByZero.errorDescription else {
            return XCTFail("missing localized description")
        }
        XCTAssertTrue(message.contains("除数"), "unexpected message: \(message)")
    }

    // MARK: - Helpers

    private func assertError(
        _ expected: CalculatorError,
        _ expression: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try Calculator.evaluate(expression), file: file, line: line) { error in
            guard let calculatorError = error as? CalculatorError else {
                return XCTFail("expected CalculatorError, got \(error)", file: file, line: line)
            }
            switch (expected, calculatorError) {
            case (.emptyExpression, .emptyExpression),
                 (.incompleteExpression, .incompleteExpression),
                 (.missingClosingParenthesis, .missingClosingParenthesis),
                 (.divisionByZero, .divisionByZero),
                 (.overflow, .overflow),
                 (.underflow, .underflow):
                break
            case (.expressionTooLong(let expectedMax), .expressionTooLong(let actualMax)):
                XCTAssertEqual(expectedMax, actualMax, file: file, line: line)
            case (.nestingTooDeep(let expectedMax), .nestingTooDeep(let actualMax)):
                XCTAssertEqual(expectedMax, actualMax, file: file, line: line)
            case (.unexpectedCharacter(let expectedCharacter), .unexpectedCharacter(let actualCharacter)):
                XCTAssertEqual(expectedCharacter, actualCharacter, file: file, line: line)
            case (.unexpectedToken(let expectedToken), .unexpectedToken(let actualToken)):
                XCTAssertEqual(expectedToken, actualToken, file: file, line: line)
            case (.invalidNumber(let expectedText), .invalidNumber(let actualText)):
                XCTAssertEqual(expectedText, actualText, file: file, line: line)
            case (.numberTooPrecise(let expectedText), .numberTooPrecise(let actualText)):
                XCTAssertEqual(expectedText, actualText, file: file, line: line)
            case (.numberOutOfRange(let expectedText), .numberOutOfRange(let actualText)):
                XCTAssertEqual(expectedText, actualText, file: file, line: line)
            default:
                XCTFail("expected \(expected), got \(calculatorError)", file: file, line: line)
            }
        }
    }
}
