import Testing
@testable import SpadesEngine

@Suite("Trick winner determination")
struct TrickTests {

    @Test("Highest card of the led suit wins when no spade is played")
    func highestOfLedSuitWins() {
        let trick = makeTrick(leader: .zero, cards("4H KH 9H 2H"))
        #expect(trick.winner == .one)
    }

    @Test("Off-suit cards cannot win")
    func offSuitCannotWin() {
        // Seat 2 discards the ace of diamonds on a heart trick. It loses to a four.
        let trick = makeTrick(leader: .zero, cards("4H 3H AD 2H"))
        #expect(trick.winner == .zero)
    }

    @Test("A single spade beats every card of the led suit")
    func spadeBeatsLedSuit() {
        let trick = makeTrick(leader: .zero, cards("AH KH 2S QH"))
        #expect(trick.winner == .two)
    }

    @Test("Highest spade wins when several are played")
    func highestSpadeWins() {
        let trick = makeTrick(leader: .zero, cards("AH 2S JS 5S"))
        #expect(trick.winner == .two)
    }

    @Test("A led spade trick is won by the highest spade")
    func spadesLed() {
        let trick = makeTrick(leader: .three, cards("9S AS 3S KS"))
        #expect(trick.winner == .zero)
    }

    @Test("Every leader position resolves correctly")
    func leaderRotation() {
        for leader in Seat.allCases {
            let trick = makeTrick(leader: leader, cards("2C 3C 4C AC"))
            #expect(trick.winner == leader.advanced(by: 3))
        }
    }

    @Test("An incomplete trick has a current winner but no winner")
    func incompleteTrick() {
        var trick = Trick(leader: .zero)
        #expect(trick.currentWinner == nil)
        #expect(trick.winner == nil)
        trick.append(Trick.Play(seat: .zero, card: card("7D")))
        #expect(trick.currentWinner == .zero)
        #expect(trick.winner == nil)
        #expect(trick.seatToPlay == .one)
    }

    @Test("Trick reports the led suit and the seat to play")
    func trickProgression() {
        var trick = Trick(leader: .two)
        trick.append(Trick.Play(seat: .two, card: card("5H")))
        #expect(trick.ledSuit == .hearts)
        #expect(trick.seatToPlay == .three)
        trick.append(Trick.Play(seat: .three, card: card("6H")))
        trick.append(Trick.Play(seat: .zero, card: card("7H")))
        #expect(trick.seatToPlay == .one)
        trick.append(Trick.Play(seat: .one, card: card("8H")))
        #expect(trick.isComplete)
        #expect(trick.seatToPlay == nil)
        #expect(trick.winner == .one)
    }
}

@Suite("Cards and deck")
struct CardTests {

    @Test("Card ids are a dense zero-based index over the whole deck")
    func idsAreDense() {
        // Bots and the renderer both index 52-element tables by `Card.id`.
        let ids = Deck.full.cards.map(\.id)
        #expect(ids.count == 52)
        #expect(Set(ids) == Set(0..<52))
    }

    @Test("A fresh deck holds every card exactly once, in canonical order")
    func deckIsComplete() {
        let deck = Deck.full
        #expect(deck.cards.count == 52)
        #expect(Set(deck.cards).count == 52)
        #expect(deck.cards == deck.cards.sorted())
    }

    @Test("Shuffling permutes without losing or duplicating a card")
    func shufflePreservesDeck() {
        var generator = SeededGenerator(seed: 1)
        let shuffled = Deck.full.shuffled(using: &generator)
        #expect(Set(shuffled.cards) == Set(Deck.full.cards))
        #expect(shuffled.cards != Deck.full.cards)
    }

    @Test("Cards sort by suit then rank and expose accessible names")
    func ordering() {
        #expect(card("2S") > card("AH"))
        #expect(card("AH") > card("KH"))
        #expect(card("QS").accessibilityName == "Queen of Spades")
        #expect(card("10D").accessibilityName == "Ten of Diamonds")
        #expect(card("JC").rank.isFace)
        #expect(!card("10C").rank.isFace)
    }

    @Test("A deal hands thirteen cards to each seat starting on the dealer's left")
    func dealOrder() {
        let hands = Deck.full.deal(startingAt: .one)
        #expect(hands[.one].contains(Card(.two, of: .clubs)), "The first card dealt goes to the first receiver")
        for seat in Seat.allCases { #expect(hands[seat].count == 13) }
    }
}
