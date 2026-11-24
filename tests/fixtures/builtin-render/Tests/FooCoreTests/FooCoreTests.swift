import Testing
@testable import FooCore

@Suite("FooCore")
struct FooCoreTests {

    @Test("Greeting names the app")
    func greetingNamesTheApp() {
        #expect(FooCore.greeting(appName: "Foo Bar") == "Welcome to Foo Bar")
    }
}
