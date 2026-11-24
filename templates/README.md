# {{APP}}

{{TAGLINE}}

Native macOS app (SwiftUI, macOS 27 or later), built with Swift Package
Manager and shell scripts; no Xcode project.

Website and manual: {{PAGES_URL}}

## Build and run

You need Xcode (for `actool`, which compiles the app icon; the command line
tools alone are not enough).

```
./run.sh            # debug build, runs in the terminal with logs (Ctrl+C quits)
./run.sh release    # optimized build, opens the app
swift test          # tests
./build.sh dist     # signed, notarized DMG (needs a Developer ID, see development_workflow.md)
```

Details: [development_workflow.md](development_workflow.md).

## License

{{#LICENSE}}
{{LICENSE_LABEL}}, see [LICENSE](LICENSE).
{{/LICENSE}}
{{^LICENSE}}
Copyright © {{YEAR}} {{AUTHOR}}. All rights reserved.
{{/LICENSE}}
