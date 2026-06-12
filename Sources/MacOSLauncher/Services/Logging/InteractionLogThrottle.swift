import QuartzCore

final class InteractionLogThrottle {
    private var lastFire: [String: CFTimeInterval] = [:]

    func shouldLog(_ key: String, interval: CFTimeInterval) -> Bool {
        let now = CACurrentMediaTime()
        let previous = lastFire[key] ?? 0
        guard now - previous >= interval else {
            return false
        }
        lastFire[key] = now
        return true
    }
}
