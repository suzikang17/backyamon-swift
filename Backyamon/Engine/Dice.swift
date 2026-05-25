import Foundation

func rollSingleDie() -> Int {
    return Int.random(in: 1...6)
}

func generateDice() -> Dice {
    let d1 = rollSingleDie()
    let d2 = rollSingleDie()
    let remaining = d1 == d2 ? [d1, d1, d1, d1] : [d1, d2]
    return Dice(values: (d1, d2), remaining: remaining)
}
