import Foundation

// Host-only SDK value stubs: the script compiles the real Demo state source on macOS.
struct FaceBounds {
    let x: Float
    let y: Float
    let width: Float
    let height: Float
}

struct FaceSearchFace {
    let bounds: FaceBounds
    let thresholdPassed: Bool
    let similarity: Float?
    let faceID: String?
}

struct FaceSearchFrame {
    let frameID: UInt64
    let imageWidth: Int
    let imageHeight: Int
    let faces: [FaceSearchFace]
}

enum FaceSearchEndReason {
    case matchFound, timeout, noFace, spoofDetected
}

struct FaceSearchResult {
    let endReason: FaceSearchEndReason
    let livenessScore: Float?
    let frame: FaceSearchFrame
}

@main
struct FaceSearchOverlayStateTests {
    static func main() {
        let a = FaceBounds(x: 20, y: 30, width: 100, height: 100)
        let b = FaceBounds(x: 25, y: 30, width: 100, height: 100)
        let pending = FaceSearchFace(bounds: a, thresholdPassed: false, similarity: nil, faceID: nil)
        let matched = FaceSearchFace(bounds: a, thresholdPassed: true, similarity: 0.94, faceID: "A")
        let low = FaceSearchFace(bounds: a, thresholdPassed: false, similarity: 0.4, faceID: nil)
        func frame(_ id: UInt64, _ faces: [FaceSearchFace]) -> FaceSearchFrame {
            FaceSearchFrame(frameID: id, imageWidth: 640, imageHeight: 480, faces: faces)
        }

        var idle = FaceSearchOverlayState()
        for id in UInt64(1)...10_000 {
            precondition(!idle.accept(frame(id, []), now: Double(id) * 0.2))
            precondition(idle.newestFrameID == id && !idle.hasVisibleFaces && idle.expiresAt == nil)
        }
        precondition(!idle.accept(frame(1, [matched]), now: 2001))
        precondition(!idle.hasVisibleFaces)
        let appeared = frame(10_001, [matched])
        precondition(idle.accept(appeared, now: 2001))
        precondition(idle.accept(frame(10_002, []), now: 2001.1))
        precondition(!idle.accept(frame(10_003, []), now: 2001.2))
        precondition(!idle.complete(FaceSearchResult(endReason: .matchFound, livenessScore: 0.97,
                                                    frame: appeared), now: 2001.25))
        precondition(!idle.hasVisibleFaces && idle.box(at: 0).title.isEmpty)
        precondition(idle.accept(frame(10_004, [pending]), now: 2001.3))
        precondition(idle.box(at: 0).title.isEmpty)
        // 迟到回调使帧到期时仍需发布一次清理，不能撤销定时器后留下旧框。
        precondition(idle.complete(FaceSearchResult(endReason: .timeout, livenessScore: nil,
                                                    frame: appeared), now: 2003))
        precondition(!idle.hasVisibleFaces)
        precondition(!idle.setAssociationEnabled(false))
        precondition(!idle.setAssociationEnabled(false))

        var schedule = FaceSearchOverlayExpirySchedule()
        precondition(!schedule.update(to: nil))
        precondition(schedule.update(to: 10))
        for _ in 0..<10_000 { precondition(!schedule.update(to: 10)) }
        for index in 0..<10_000 { precondition(!schedule.update(to: 10 + Double(index) / 10)) }
        precondition(schedule.deadline == 10)
        precondition(schedule.update(to: 9))
        precondition(!schedule.update(to: 11))
        precondition(schedule.update(to: nil))
        precondition(!schedule.update(to: nil))
        precondition(schedule.update(to: 11))
        schedule.reset()
        precondition(schedule.deadline == nil && schedule.update(to: 11))

        var earlyCheck = FaceSearchOverlayState()
        earlyCheck.accept(frame(1, [pending]), now: 0)
        precondition(schedule.update(to: earlyCheck.expiresAt))
        earlyCheck.accept(frame(2, [pending]), now: 1)
        precondition(!schedule.update(to: earlyCheck.expiresAt))
        precondition(!earlyCheck.expire(now: 1.2) && earlyCheck.hasVisibleFaces)
        schedule.reset()
        precondition(schedule.update(to: earlyCheck.expiresAt))
        precondition(earlyCheck.expire(now: 2.2) && !earlyCheck.hasVisibleFaces)

        var overlay = FaceSearchOverlayState()
        overlay.accept(frame(1, [pending]), now: 10)
        precondition(overlay.box(at: 0).color == .pending && overlay.box(at: 0).title.isEmpty)
        overlay.accept(frame(1, [matched]), now: 10.1)
        precondition(overlay.box(at: 0).color == .pending) // 相似度达标，仍等最终结论。
        overlay.complete(FaceSearchResult(endReason: .matchFound, livenessScore: 0.97,
                                          frame: frame(1, [matched])), now: 10.2)
        precondition(overlay.box(at: 0).color == .matched)
        precondition(overlay.box(at: 0).title == "A")
        precondition(overlay.box(at: 0).details == "相似度 0.940 · 活体 0.970")
        for _ in 0..<10_000 {
            precondition(overlay.box(at: 0).details == "相似度 0.940 · 活体 0.970")
        }

        overlay.accept(frame(2, [pending]), now: 10.25)
        precondition(overlay.box(at: 0).color == .matched) // 唯一相邻框可短时借用。
        overlay.accept(frame(2, [low]), now: 10.3)
        precondition(overlay.box(at: 0).color == .unmatched) // 新评分覆盖旧绿框。
        overlay.expire(now: 11.1)
        precondition(overlay.frame != nil && overlay.box(at: 0).color == .unmatched)
        overlay.expire(now: 11.31)
        precondition(overlay.frame != nil && overlay.box(at: 0).color == .pending)
        overlay.expire(now: 11.46)
        precondition(overlay.frame == nil)

        overlay.accept(frame(3, [pending]), now: 12)
        overlay.accept(frame(3, [low]), now: 12.1)
        precondition(overlay.box(at: 0).color == .unmatched)
        precondition(overlay.box(at: 0).title == "未匹配")
        precondition(overlay.box(at: 0).details.isEmpty)
        overlay.accept(frame(3, [low]), now: 12.8)
        overlay.expire(now: 13.11)
        precondition(overlay.box(at: 0).color == .pending) // 重复评分没有延长期限。

        overlay.clear()
        overlay.accept(frame(4, [pending]), now: 20)
        overlay.accept(frame(4, [matched]), now: 20.1)
        overlay.complete(FaceSearchResult(endReason: .spoofDetected, livenessScore: 0.2,
                                          frame: frame(4, [matched])), now: 20.2)
        precondition(overlay.box(at: 0).color == .unmatched)
        precondition(overlay.box(at: 0).title == "A · 活体未通过")
        precondition(overlay.box(at: 0).details == "相似度 0.940 · 活体 0.200")

        overlay.clear()
        let bothLow = frame(8, [low])
        overlay.accept(bothLow, now: 21)
        overlay.complete(FaceSearchResult(endReason: .spoofDetected, livenessScore: 0.42,
                                          frame: bothLow), now: 21.1)
        precondition(overlay.box(at: 0).color == .unmatched)
        precondition(overlay.box(at: 0).title == "未匹配 · 活体未通过")
        precondition(overlay.box(at: 0).details == "活体 0.420")
        precondition(bothLow.faces[0].similarity == 0.4 && bothLow.faces[0].faceID == nil)

        overlay.clear()
        overlay.accept(frame(7, [pending]), now: 25)
        overlay.complete(FaceSearchResult(endReason: .spoofDetected, livenessScore: 0.1,
                                          frame: frame(7, [matched])), now: 25.1)
        precondition(overlay.box(at: 0).color == .unmatched)
        precondition(overlay.box(at: 0).details == "相似度 0.940 · 活体 0.100")

        overlay.clear()
        overlay.accept(frame(5, [matched]), now: 30)
        overlay.complete(FaceSearchResult(endReason: .matchFound, livenessScore: nil,
                                          frame: frame(5, [matched])), now: 30.1)
        let second = FaceSearchFace(bounds: b, thresholdPassed: false, similarity: nil, faceID: nil)
        overlay.accept(frame(6, [pending, second]), now: 30.2)
        precondition(overlay.box(at: 0).color == .pending && overlay.box(at: 1).color == .pending)
        overlay.rejectScores(through: 6)
        precondition(overlay.frame != nil && overlay.box(at: 0).color == .pending)
        var multiple = FaceSearchOverlayState()
        let five = (0..<5).map { index in
            FaceSearchFace(bounds: FaceBounds(x: Float(index * 120), y: 30, width: 100, height: 100),
                           thresholdPassed: true, similarity: 0.94, faceID: "face-\(index)")
        }
        multiple.accept(frame(1, five), now: 0)
        for index in 0..<5 { precondition(multiple.box(at: index).title == "face-\(index)") }
        multiple.accept(frame(1, five), now: 0.9)
        precondition(multiple.expiresAt == 1, "duplicate five-face scores must not extend their deadline")
        multiple.expire(now: 1)
        for index in 0..<5 { precondition(multiple.box(at: index).title.isEmpty) }
        multiple.accept(frame(2, five), now: 1.1)
        precondition(multiple.expiresAt == 2.1)
        for index in 0..<5 { precondition(multiple.box(at: index).title == "face-\(index)") }
        print("Face search overlay: final colors, five-face bit marks, cached labels, expiry/idle publication and 10000 extended deadlines")
    }
}
