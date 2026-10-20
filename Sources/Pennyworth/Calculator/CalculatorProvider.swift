import Foundation

enum CalculatorProvider {
    static func result(for request: SearchRequest) throws -> SearchResult? {
        guard request.intent == .calculator else { return nil }
        let value = try Calculator.evaluate(request.query)
        return SearchResult(id: "calculator:\(request.query)", title: value,
                            subtitle: "\(request.query)  ·  回车复制结果", symbol: "equal.square",
                            action: .copyText(value))
    }
}
