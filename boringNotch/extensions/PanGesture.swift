//
//  PanGesture.swift
//  boringNotch
//
//  Created by Richard Kunkli on 21/08/2024.
//

import AppKit
import SwiftUI

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    @ViewBuilder
    func panGesture(
        direction: PanDirection,
        threshold: CGFloat = 4,
        normalizeDeviceDirection: Bool = false,
        allowsMouseDrag: Bool = true,
        requiresPreciseScrollingDeltas: Bool = false,
        coalescesMomentum: Bool = false,
        action: @escaping (CGFloat, NSEvent.Phase) -> Void
    ) -> some View {
        let scrollMonitor = ScrollMonitor(
            direction: direction,
            threshold: threshold,
            normalizeDeviceDirection: normalizeDeviceDirection,
            requiresPreciseScrollingDeltas: requiresPreciseScrollingDeltas,
            coalescesMomentum: coalescesMomentum,
            action: action
        )

        if allowsMouseDrag {
            self.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(scrollMonitor)
        } else {
            self.background(scrollMonitor)
        }
    }

    func trackpadHorizontalSwipe(
        enabled: Bool,
        threshold: CGFloat,
        action: @escaping (PanDirection) -> Void
    ) -> some View {
        background(
            TrackpadHorizontalSwipeMonitor(
                enabled: enabled,
                threshold: threshold,
                action: action
            )
        )
    }
}

private struct TrackpadHorizontalSwipeMonitor: NSViewRepresentable {
    let enabled: Bool
    let threshold: CGFloat
    let action: (PanDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(enabled: enabled, threshold: threshold, action: action)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(enabled: enabled, threshold: threshold, action: action)
    }

    @MainActor
    final class Coordinator: NSObject {
        private var enabled: Bool
        private var threshold: CGFloat
        private var action: (PanDirection) -> Void
        private var monitor: Any?
        private var accumulatedX: CGFloat = 0
        private var hasTriggered = false
        private var resetTask: Task<Void, Never>?
        private let noiseThreshold: CGFloat = 0.2

        init(enabled: Bool, threshold: CGFloat, action: @escaping (PanDirection) -> Void) {
            self.enabled = enabled
            self.threshold = threshold
            self.action = action
        }

        func update(
            enabled: Bool,
            threshold: CGFloat,
            action: @escaping (PanDirection) -> Void
        ) {
            if self.enabled && !enabled {
                resetGesture()
            }
            self.enabled = enabled
            self.threshold = threshold
            self.action = action
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) {
                [weak self, weak view] event in
                guard let self,
                      let view,
                      event.window === view.window,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil))
                else { return event }

                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            resetGesture()
        }

        private func handleScroll(_ event: NSEvent) {
            guard enabled, event.hasPreciseScrollingDeltas else {
                resetGesture()
                return
            }

            // Momentum belongs to the gesture that has already completed. Ignoring it
            // guarantees that a single physical swipe can change at most one track.
            guard event.momentumPhase.isEmpty else { return }

            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                resetGesture()
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                resetGesture()
                return
            }

            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            guard absDX >= 1.5 * absDY else { return }

            let directionMultiplier: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            let deltaX = event.scrollingDeltaX * directionMultiplier
            guard abs(deltaX) > noiseThreshold else {
                scheduleResetTimeout()
                return
            }

            if accumulatedX == 0 || (accumulatedX > 0) == (deltaX > 0) {
                accumulatedX += deltaX
            } else {
                accumulatedX = deltaX
            }

            if !hasTriggered && abs(accumulatedX) >= threshold {
                hasTriggered = true
                action(accumulatedX < 0 ? .left : .right)
            }

            scheduleResetTimeout()
        }

        private func scheduleResetTimeout() {
            resetTask?.cancel()
            resetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self else { return }
                self.accumulatedX = 0
                self.hasTriggered = false
                self.resetTask = nil
            }
        }

        private func resetGesture() {
            resetTask?.cancel()
            resetTask = nil
            accumulatedX = 0
            hasTriggered = false
        }
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let normalizeDeviceDirection: Bool
    let requiresPreciseScrollingDeltas: Bool
    let coalescesMomentum: Bool
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator { 
        Coordinator(
            direction: direction,
            threshold: threshold,
            normalizeDeviceDirection: normalizeDeviceDirection,
            requiresPreciseScrollingDeltas: requiresPreciseScrollingDeltas,
            coalescesMomentum: coalescesMomentum,
            action: action
        )
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        private let normalizeDeviceDirection: Bool
        private let requiresPreciseScrollingDeltas: Bool
        private let coalescesMomentum: Bool
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var active = false
        private var endTask: Task<Void, Never>?
        private let noiseThreshold: CGFloat = 0.2

        init(
            direction: PanDirection,
            threshold: CGFloat,
            normalizeDeviceDirection: Bool,
            requiresPreciseScrollingDeltas: Bool,
            coalescesMomentum: Bool,
            action: @escaping (CGFloat, NSEvent.Phase) -> Void
        ) {
            self.direction = direction
            self.threshold = threshold
            self.normalizeDeviceDirection = normalizeDeviceDirection
            self.requiresPreciseScrollingDeltas = requiresPreciseScrollingDeltas
            self.coalescesMomentum = coalescesMomentum
            self.action = action
        }

        private func scheduleEndTimeout() {
            // Cancel any existing scheduled end and schedule a new one.
            endTask?.cancel()
            endTask = Task { @MainActor in
                // If no new scroll event arrives within this window, consider the gesture ended.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self,
                      let view,
                      event.window === view.window,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil))
                else { return event }
                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            accumulated = 0
            active = false
            endTask?.cancel()
            endTask = nil
        }

        private func handleScroll(_ event: NSEvent) {
            guard !requiresPreciseScrollingDeltas || event.hasPreciseScrollingDeltas else { return }

            if event.momentumPhase == .ended || (event.phase == .ended && !coalescesMomentum) {
                endTask?.cancel()
                endTask = nil
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                return
            }

            // A trackpad's momentum phase can begin immediately after the physical
            // phase ends. Keep the same accumulation alive until momentum finishes.
            if event.phase == .ended {
                scheduleEndTimeout()
                return
            }

            // Only consider scroll events that are primarily along the configured axis.
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            // Require the movement along the gesture axis to be at least 1.5x the orthogonal axis.
            let axisDominanceFactor: CGFloat = 1.5
            let isAxisDominant: Bool = direction.isHorizontal ? (absDX >= axisDominanceFactor * absDY) : (absDY >= axisDominanceFactor * absDX)
            guard isAxisDominant else { return }

            // Scale non-precise (mouse wheel) scrolling deltas so they feel similar to
            // trackpad gestures.
            let directionMultiplier: CGFloat = normalizeDeviceDirection
                ? (event.isDirectionInvertedFromDevice ? 1 : -1)
                : 1
            let raw = direction.signed(
                deltaX: event.scrollingDeltaX * directionMultiplier,
                deltaY: event.scrollingDeltaY * directionMultiplier
            )
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let s = raw * scale
            guard s.magnitude > noiseThreshold else { return }
            accumulated = s > 0 ? accumulated + s : 0

            if !active && accumulated >= threshold {
                active = true
                action(accumulated.magnitude, .began)
            } else if active {
                action(accumulated.magnitude, .changed)
            }
            // Schedule a timeout to end the gesture if no further scroll events arrive.
            scheduleEndTimeout()
        }
    }
}
