import AppKit

// Top-level code in main.swift runs on the main thread, but the compiler (Swift 6.x in Swift 5
// mode) does not treat it as @MainActor. assumeIsolated makes that explicit.
MainActor.assumeIsolated {
    let options = LaunchOptions(arguments: CommandLine.arguments)

    // `--snapshot` renders and exits before any window or status item exists.
    if options.snapshot != nil {
        exit(Snapshot.run(options))
    }

    let application = NSApplication.shared
    let appDelegate = AppDelegate(options: options)
    application.delegate = appDelegate
    application.run()
}
