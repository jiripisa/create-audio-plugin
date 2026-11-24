import Testing
@testable import {{APP}}Core

@Suite("{{APP}}Core")
struct {{APP}}CoreTests {

    @Test("Greeting names the app")
    func greetingNamesTheApp() {
        #expect({{APP}}Core.greeting(appName: "{{APP}}") == "Welcome to {{APP}}")
    }
}
