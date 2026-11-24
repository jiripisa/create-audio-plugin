# Foo Bar

does x

Native macOS app (SwiftUI, macOS 14 or later), built with Swift Package
Manager and shell scripts; no Xcode project.

Website and manual: https://someone.github.io/foo/

## Build and run

You need the Xcode command line tools.

```
./run.sh            # debug build, runs in the terminal with logs (Ctrl+C quits)
./run.sh release    # optimized build, opens the app
swift test          # tests
./build.sh dist     # signed, notarized DMG (needs a Developer ID, see development_workflow.md)
```

Details: [development_workflow.md](development_workflow.md).

## License

Copyright © 2026 A B. All rights reserved.
