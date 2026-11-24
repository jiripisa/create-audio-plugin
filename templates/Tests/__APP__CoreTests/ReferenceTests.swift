import Testing
import {{APP}}Reference

@Suite("Reference") struct ReferenceTests {
    @Test("The prototype renders its melody, and renders it the same twice")
    func melody() {
        let render = PrototypeScores.render(named: "01_tone_melody")
        let events = PrototypeScores.events(render, rate: 48_000)
        let frames = PrototypeScores.frames(render, rate: 48_000)
        let params = [PrototypeScores.referenceParams([:])]
        let a = PrototypeScores.referenceRender(events, frames: frames, params: params, rate: 48_000, oversampled: false)
        let b = PrototypeScores.referenceRender(events, frames: frames, params: params, rate: 48_000, oversampled: false)
        #expect(a == b)
        #expect(a.count == Int(render.seconds * 48_000))
        #expect((a.map(abs).max() ?? 0) > 0.5)
        #expect(a.suffix(4_800).allSatisfy { $0 == 0 })                 // every note over by the end
    }

    @Test("Percent knobs become the prototype's fractions")
    func conversion() {
        let p = PrototypeScores.referenceParams(["brightness": 50, "velsens": 20, "attack": 100])
        #expect(p.brightness == 0.5 && abs(p.velsens - 0.2) < 1e-6 && abs(p.attack - 100) < 1e-3)
    }

    @Test("The prototype's defaults are the engine's")
    func defaults() {
        var p = {{APP}}RefParams()
        {{APP_C}}_ref_default_params(&p)
        let ours = PrototypeScores.referenceParams([:])
        // The engine holds a knob as its position: a value comes back to within a rounding.
        #expect(abs(p.attack - ours.attack) < 1e-4 && abs(p.decay - ours.decay) < 1e-5 && abs(p.release - ours.release) < 1e-5)
        #expect(abs(p.brightness - ours.brightness) < 1e-6 && abs(p.velsens - ours.velsens) < 1e-6)
    }
}
