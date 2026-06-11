/// 纯函数形式的 Tile 顺序变换器，便于进行确定性测试。
enum TileOrderMover {
    /// 返回将拖拽项移动到目标项之前的新顺序。
    ///
    /// 由 `LauncherStore.previewMoveTile` 调用，不执行持久化。
    ///
    /// - Parameters:
    ///   - draggedID: 被拖拽 Tile 的标识。
    ///   - targetID: 目标 Tile 的标识，拖拽项会插入到它之前。
    ///   - order: 变换前的完整 Tile 顺序。
    /// - Returns: 调整后的新顺序；参数无效时原样返回。
    static func moving(_ draggedID: String, before targetID: String, in order: [String]) -> [String] {
        guard draggedID != targetID,
              let fromIndex = order.firstIndex(of: draggedID),
              let toIndex = order.firstIndex(of: targetID) else {
            return order
        }

        var result = order
        let moved = result.remove(at: fromIndex)
        let adjustedTargetIndex = fromIndex < toIndex ? toIndex - 1 : toIndex
        result.insert(moved, at: min(adjustedTargetIndex, result.count))
        return result
    }
}
