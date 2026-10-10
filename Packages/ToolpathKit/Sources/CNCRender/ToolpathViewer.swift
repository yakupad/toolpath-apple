import CNCDesign
import CNCKit
import SwiftUI

/// Interactive viewer: one-finger drag orbits, pinch zooms, two-finger /
/// trackpad drag pans, double-tap animates to fit. In 2D mode orbiting is
/// disabled and drag pans.
public struct ToolpathViewer: View {
    let geometry: ToolpathGeometry
    @Binding var camera: OrbitCamera
    let is3D: Bool
    let filter: MoveFilter
    let cursor: SimulationPoint?
    let focusedMove: Int?
    let drawProgress: Double
    let insets: EdgeInsetsValue

    @State private var dragBase: OrbitCamera?
    @State private var zoomBase: Double?

    public init(
        geometry: ToolpathGeometry,
        camera: Binding<OrbitCamera>,
        is3D: Bool = true,
        filter: MoveFilter = MoveFilter(),
        cursor: SimulationPoint? = nil,
        focusedMove: Int? = nil,
        drawProgress: Double = 1,
        insets: EdgeInsetsValue = .zero
    ) {
        self.insets = insets
        self.geometry = geometry
        self._camera = camera
        self.is3D = is3D
        self.filter = filter
        self.cursor = cursor
        self.focusedMove = focusedMove
        self.drawProgress = drawProgress
    }

    public var body: some View {
        ToolpathCanvas(
            geometry: geometry,
            camera: camera,
            filter: filter,
            drawProgress: drawProgress,
            cursor: cursor,
            focusedMove: focusedMove,
            insets: insets
        )
        .contentShape(.rect)
        .gesture(dragGesture.simultaneously(with: magnifyGesture))
        .onTapGesture(count: 2) { fit() }
        .accessibilityAction(named: Text("Fit to view", bundle: .module)) { fit() }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let base = dragBase ?? camera
                if dragBase == nil { dragBase = camera }
                var next = base
                if is3D {
                    next.yaw = base.yaw + value.translation.width * 0.01
                    next.pitch = min(max(base.pitch + value.translation.height * 0.01, -.pi / 2), .pi / 2)
                } else {
                    next.pan = CGSize(width: base.pan.width + value.translation.width,
                                      height: base.pan.height + value.translation.height)
                }
                camera = next
            }
            .onEnded { _ in dragBase = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = zoomBase ?? camera.zoom
                if zoomBase == nil { zoomBase = camera.zoom }
                camera.zoom = min(max(base * value.magnification, 0.2), 40)
            }
            .onEnded { _ in zoomBase = nil }
    }

    private func fit() {
        withAnimation(.spring(duration: 0.5)) {
            camera.zoom = 1
            camera.pan = .zero
        }
    }
}

extension OrbitCamera: Animatable {
    public var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, AnimatablePair<Double, Double>>> {
        get { AnimatablePair(AnimatablePair(yaw, pitch), AnimatablePair(zoom, AnimatablePair(pan.width, pan.height))) }
        set {
            yaw = newValue.first.first
            pitch = newValue.first.second
            zoom = newValue.second.first
            pan = CGSize(width: newValue.second.second.first, height: newValue.second.second.second)
        }
    }
}
