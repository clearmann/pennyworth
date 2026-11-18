import CoreGraphics
import Foundation

/// A window under the cursor, with its bounds converted to display-local AppKit points.
struct WindowHit: Equatable {
    let windowID: CGWindowID
    let localBounds: CGRect
}

/// Pure front-to-back window hit testing with PixPin-style eligibility filtering.
struct WindowHitTester {
    let ownPID: pid_t
    let minimumSize: CGSize

    init(ownPID: pid_t, minimumSize: CGSize = CGSize(width: 40, height: 40)) {
        self.ownPID = ownPID
        self.minimumSize = minimumSize
    }

    func eligible(_ window: WindowDescriptor) -> Bool {
        window.ownerPID != ownPID
            && window.layer == 0
            && window.isOnscreen
            && window.alpha > 0.01
            && window.sharingState != 0 // CGWindowSharingNone must never be selectable.
            && window.quartzBounds.width >= minimumSize.width
            && window.quartzBounds.height >= minimumSize.height
    }

    func hit(atLocalPoint point: CGPoint, display: DisplayDescriptor, windows: [WindowDescriptor],
             mainDisplayHeight: CGFloat) -> WindowHit? {
        for window in windows where eligible(window) {
            let local = ScreenGeometry.localRect(forQuartzGlobal: window.quartzBounds, in: display,
                                                 mainDisplayHeight: mainDisplayHeight)
            if local.contains(point) {
                return WindowHit(windowID: window.id, localBounds: local)
            }
        }
        return nil
    }
}
