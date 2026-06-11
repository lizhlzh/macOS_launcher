import Testing
@testable import Luma

@Test
func movingForwardUsesAdjustedTargetIndex() {
    let result = TileOrderMover.moving("A", before: "C", in: ["A", "B", "C", "D"])
    #expect(result == ["B", "A", "C", "D"])
}

@Test
func movingBackwardKeepsTargetPosition() {
    let result = TileOrderMover.moving("D", before: "B", in: ["A", "B", "C", "D"])
    #expect(result == ["A", "D", "B", "C"])
}

@Test
func unknownTileLeavesOrderUnchanged() {
    let order = ["A", "B", "C", "D"]
    #expect(TileOrderMover.moving("X", before: "B", in: order) == order)
}
