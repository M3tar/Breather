import Foundation

/// Coordinates are in logical pixels; the renderer scales the whole lane uniformly.
struct DinosaurSceneModel {
    enum Pose: Equatable { case standing, walkA, walkB, jumping }
    struct Obstacle: Equatable {
        let x: Double
        let height: Double
        let width: Double
    }
    struct Frame {
        let pose: Pose
        let jumpHeight: Double
        let groundOffset: Double
        let obstacles: [Obstacle]
    }

    static let speed = 92.0
    static let jumpDuration = 0.9
    static let strideDuration = 0.22
    static let dinosaurX = 76.0
    static let dinosaurWidth = 26.0
    static let laneWidth = 420.0
    private let seed: UInt64

    init(seed: UInt64) { self.seed = seed }

    /// Finish only the jump already in progress, then park the scene. The caller
    /// chooses when to wind down from the authoritative remaining break time.
    func finishTime(after elapsed: Double) -> Double {
        for crossing in crossings(through: elapsed + Self.jumpDuration / 2) {
            if elapsed >= crossing.time - Self.jumpDuration / 2,
               elapsed < crossing.time + Self.jumpDuration / 2 {
                return crossing.time + Self.jumpDuration / 2
            }
        }
        return elapsed
    }

    func frame(elapsed: Double, stopAt: Double? = nil, animated: Bool) -> Frame {
        guard animated else {
            return Frame(pose: .standing, jumpHeight: 0, groundOffset: 0,
                         obstacles: [Obstacle(x: 294, height: 20, width: 9)])
        }
        let time = max(0, min(elapsed, stopAt ?? elapsed))
        var obstacles: [Obstacle] = []
        var jumpHeight = 0.0
        // Enumerate only potential crossings up to the visible horizon. Deterministic
        // per-session intervals avoid random changes on redraw or screen changes.
        for (crossing, index) in crossings(through: time + Self.laneWidth / Self.speed + 1) {
            let jumpStart = crossing - Self.jumpDuration / 2
            let jumpEnd = crossing + Self.jumpDuration / 2
            let alreadyJumping = time >= jumpStart && time < jumpEnd
            let x = Self.dinosaurX + Self.dinosaurWidth / 2
                + (crossing - time) * Self.speed - 4.5
            if x > -12 && x < Self.laneWidth {
                obstacles.append(Obstacle(x: x, height: index.isMultiple(of: 2) ? 18 : 22, width: 9))
            }
            if alreadyJumping {
                let phase = (time - jumpStart) / Self.jumpDuration
                jumpHeight = 46 * sin(.pi * phase)
            }
        }
        let standing = stopAt.map { elapsed >= $0 } ?? false
        let pose: Pose = jumpHeight > 0 ? .jumping
            : standing ? .standing
            : Int(time / Self.strideDuration).isMultiple(of: 2) ? .walkA : .walkB
        return Frame(pose: pose, jumpHeight: jumpHeight,
                     groundOffset: (time * Self.speed).truncatingRemainder(dividingBy: 448),
                     obstacles: obstacles)
    }

    private func crossings(through horizon: Double) -> [(time: Double, index: Int)] {
        var result: [(Double, Int)] = []
        var crossing = 4.0
        var index = 0
        while crossing <= horizon {
            result.append((crossing, index))
            let variation = (seed &+ UInt64(index) &* 6364136223846793005) % 5
            crossing += 6 + Double(variation)
            index += 1
        }
        return result
    }
}
