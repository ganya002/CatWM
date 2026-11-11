@testable import CatWMKit
import Foundation
import Testing

@Suite struct JSONParseTests {
    private func parse(_ text: String) -> JSON? { JSON.parse(Data(text.utf8)) }

    @Test func parsesEachKindOfValue() {
        let text = #"{"a":[1,2.5,-0,3.0,1e2],"b":true,"c":null,"d":"é","e":{"f":false},"g":[]}"#

        #expect(parse(text) == ["a": [1, 2.5, 0, 3, 100], "b": true, "c": .null, "d": "é", "e": ["f": false], "g": []])
    }

    @Test func readsIntegersAtTheEdgesOfTheirRange() {
        #expect(parse("9223372036854775807") == .int(Int.max))
        #expect(parse("-9223372036854775808") == .int(Int.min))
        #expect(parse("9223372036854775808") == .number(9_223_372_036_854_775_808))
        #expect(parse("12345678901234567890") == .number(12_345_678_901_234_567_890))
    }

    @Test func keepsABooleanApartFromANumber() {
        #expect(parse("[true,1,false,0]") == [true, 1, false, 0])
    }

    @Test func rejectsWhatIsNotJSON() {
        for text in ["", " ", "NaN", "1e999", "[1 2]", "{\"a\":1}x"] {
            #expect(parse(text) == nil, "\(text)")
        }
    }
}
