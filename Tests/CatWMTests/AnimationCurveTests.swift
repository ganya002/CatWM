@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

struct AnimationCurveTests {
    @Test func bouncePreservesSampledTrajectory() {
        let samples: [(Double, [Double])] = [
            (0.0, [
                0.0, 0.0123765625, 0.04950625, 0.1113890625,
                0.198025, 0.30941406250000003, 0.44555625, 0.6064515625000001,
                0.7921, 0.9992515625, 0.94515625, 0.9158140625,
                0.911225, 0.9313890625, 0.97630625, 0.9923515625,
                1.0
            ]),
            (0.19942402615592697, [
                0.0, 0.018183404045799212, 0.07273361618319685, 0.1636506364121929,
                0.2909344647327874, 0.4545851011449802, 0.6546025456487716, 0.8909867982441615,
                0.9463777208827108, 0.8833831697896498, 0.8567554267881873, 0.8664944918783232,
                0.9126003650600575, 0.9950730463333901, 0.979452679409454, 0.9933419881231178,
                1.0
            ]),
            (0.25, [
                0.0, 0.019740250000000004, 0.07896100000000002, 0.17766225000000002,
                0.31584400000000007, 0.4935062500000002, 0.7106490000000001, 0.9672722500000001,
                0.9161759999999999, 0.8583602499999999, 0.840025, 0.86117025,
                0.9217960000000001, 0.99222225, 0.974449, 0.9961562500000001,
                1.0
            ]),
            (0.5, [
                0.0, 0.03228759765625, 0.129150390625, 0.29058837890625,
                0.5166015625, 0.80718994140625, 0.927978515625, 0.80865478515625,
                0.75390625, 0.76373291015625, 0.838134765625, 0.97711181640625,
                0.9462890625, 0.94488525390625, 0.996337890625, 0.98931884765625,
                1.0
            ]),
            (0.75, [
                0.0, 0.055422576400000034, 0.22169030560000014, 0.4988031876000003,
                0.8867612224000005, 0.8188444099999997, 0.6751487503999998, 0.6422982436,
                0.7202928896000003, 0.9091326884000004, 0.9127536399999998, 0.8712773443999999,
                0.9406462016000002, 0.9590502915999999, 0.9789056144000002, 0.98567393,
                1.0
            ]),
            (1.0, [
                0.0, 0.11380681973922054, 0.45522727895688214, 0.9832642074029854,
                0.6329128888275293, 0.5101752097305141, 0.6150511701119403, 0.9475407699718074,
                0.7964492915101162, 0.7812668306018656, 0.9936980091720561, 0.8824979113381883,
                0.9881268310577611, 0.9486697962075253, 0.9718275970592806, 0.9897949181236644,
                1.0
            ])
        ]
        for (bounce, values) in samples {
            for (step, expected) in values.enumerated() {
                let actual = AnimationCurve.bounce.progress(Double(step) / 16, bounce: bounce)
                #expect(abs(actual - expected) < 1e-12)
            }
        }
    }

    @Test(arguments: [0.0, 0.25, 0.5, 0.75, 1.0])
    func bounceHasContinuousLandingsAndPeaks(bounce: Double) {
        let restitution = 0.3 + 0.4 * bounce
        let count = Int(ceil(log(0.003) / (2 * log(restitution)))) - 1
        let arcSum = 2 * restitution * (1 - pow(restitution, Double(count))) / (1 - restitution)
        let total = 1 + arcSum
        var landing = 1.0
        #expect(abs(AnimationCurve.bounce.progress(landing / total, bounce: bounce) - 1) < 1e-12)
        for arc in 1...count {
            let height = pow(restitution, Double(arc))
            let peak = (landing + height) / total
            #expect(abs(AnimationCurve.bounce.progress(peak, bounce: bounce) - (1 - height * height)) < 1e-12)
            landing += 2 * height
            let time = landing / total
            #expect(abs(AnimationCurve.bounce.progress(time, bounce: bounce) - 1) < 1e-12)
        }
        #expect(AnimationCurve.bounce.progress(-1, bounce: bounce) == 0)
        #expect(AnimationCurve.bounce.progress(2, bounce: bounce) == 1)
    }
}
