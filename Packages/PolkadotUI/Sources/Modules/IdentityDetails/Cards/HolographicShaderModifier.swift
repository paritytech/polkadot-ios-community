import SwiftUI

// Colours the view it's applied to with a gyroscope-driven `colorEffect` shader,
// clipped to the view's shape. Apply it to anything:
//
//   Rectangle().holographicShader(shader: HolographicShaders.iridescentShine)        // a card surface
//   Image(.someWordmark).holographicShader(lagged: true, shader: …)           // a wordmark
//

public extension View {
    func holographicShader(
        isActive: Bool = true,
        lagged: Bool = false,
        shader: @escaping (CGSize, CGPoint) -> Shader
    ) -> some View {
        modifier(
            HolographicShaderModifier(
                isActive: isActive,
                lagged: lagged,
                shader: shader
            )
        )
    }
}

struct HolographicShaderModifier: ViewModifier {
    let isActive: Bool
    let lagged: Bool
    let shader: (CGSize, CGPoint) -> Shader

    private var motion: HolographicCardMotion { .shared }

    func body(content: Content) -> some View {
        if isActive {
            ShaderFillView(
                tilt: lagged ? motion.delayedTilt : motion.tilt,
                shader: shader
            )
            .mask { content }
            .onAppear { motion.retain() }
            .onDisappear { motion.release() }
        } else {
            content
        }
    }
}

// Fills its bounds with the shader, fed the current tilt.
struct ShaderFillView: View {
    let tilt: CGPoint
    let shader: (CGSize, CGPoint) -> Shader

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .colorEffect(shader(geo.size, tilt))
        }
    }
}
