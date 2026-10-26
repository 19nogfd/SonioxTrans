import AppKit
import SwiftUI

// This file is the entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Runs the main event loop
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
