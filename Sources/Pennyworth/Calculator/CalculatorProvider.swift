import Foundation

enum CalculatorProvider {
    static func result(for request: SearchRequest) throws -> SearchResult? {
        guard request.intent == .calculator else { return nil }
        let value = try Calculator.evaluate(request.query)
        return SearchResult(id: "calculator:\(request.query)", title: value,
                            subtitle: L10n.format("calculator.result.subtitle", request.query), symbol: "equal.square",
                            action: .copyText(value))
    }
}
