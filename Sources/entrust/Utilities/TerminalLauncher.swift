import Foundation

/// Launches commands in a new terminal window
enum TerminalLauncher {
    /// Launch a command in a new terminal window
    /// - Parameters:
    ///   - command: The command to run
    ///   - workingDirectory: The directory to run the command in
    ///   - title: Optional window title
    static func launch(command: String, workingDirectory: String? = nil, title: String? = nil) async throws {
        #if os(macOS)
        try await launchMacOS(command: command, workingDirectory: workingDirectory, title: title)
        #elseif os(Linux)
        try await launchLinux(command: command, workingDirectory: workingDirectory, title: title)
        #endif
    }

    #if os(macOS)
    /// Launch command in new macOS terminal
    private static func launchMacOS(command: String, workingDirectory: String?, title: String?) async throws {
        // Detect which terminal app to use (Terminal.app, iTerm2, or fallback)
        let terminal = detectMacOSTerminal()

        switch terminal {
        case .terminal:
            try await launchWithTerminalApp(command: command, workingDirectory: workingDirectory, title: title)
        case .iterm2:
            try await launchWithITerm2(command: command, workingDirectory: workingDirectory, title: title)
        }
    }

    private enum MacOSTerminal {
        case terminal
        case iterm2
    }

    private static func detectMacOSTerminal() -> MacOSTerminal {
        // Check if iTerm2 is running or installed
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", "tell application \"System Events\" to exists application process \"iTerm2\""]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               output == "true" {
                return .iterm2
            }
        } catch {
            // Fall through to Terminal.app
        }

        return .terminal
    }

    private static func launchWithTerminalApp(command: String, workingDirectory: String?, title: String?) async throws {
        var script = """
        tell application "Terminal"
            activate
            do script "
        """

        if let workingDirectory = workingDirectory {
            script += "cd '\(workingDirectory)' && "
        }

        script += command.replacingOccurrences(of: "\"", with: "\\\"")
        script += "\""

        if let title = title {
            script += """

                set custom title of front window to "\(title)"
            """
        }

        script += """

        end tell
        """

        try await Shell.run("osascript", "-e", script)
    }

    private static func launchWithITerm2(command: String, workingDirectory: String?, title: String?) async throws {
        var script = """
        tell application "iTerm"
            activate
            create window with default profile
            tell current session of current window
        """

        if let workingDirectory = workingDirectory {
            script += """

                write text "cd '\(workingDirectory)'"
            """
        }

        script += """

                write text "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
        """

        if let title = title {
            script += """

                set name to "\(title)"
            """
        }

        script += """

            end tell
        end tell
        """

        try await Shell.run("osascript", "-e", script)
    }
    #endif

    #if os(Linux)
    /// Launch command in new Linux terminal
    private static func launchLinux(command: String, workingDirectory: String?, title: String?) async throws {
        // Try common Linux terminal emulators in order of preference
        let terminals = [
            "gnome-terminal",
            "konsole",
            "xfce4-terminal",
            "xterm"
        ]

        for terminal in terminals {
            // Check if terminal is available
            do {
                _ = try await Shell.run("which", terminal)

                // Found a terminal, use it
                var args: [String] = []

                switch terminal {
                case "gnome-terminal":
                    args = ["--"]
                    if let workingDirectory = workingDirectory {
                        args.append(contentsOf: ["--working-directory=\(workingDirectory)"])
                    }
                    if let title = title {
                        args.append(contentsOf: ["--title=\(title)"])
                    }
                    args.append(contentsOf: ["/bin/bash", "-c", command])

                case "konsole":
                    if let workingDirectory = workingDirectory {
                        args.append(contentsOf: ["--workdir", workingDirectory])
                    }
                    if let title = title {
                        args.append(contentsOf: ["--title", title])
                    }
                    args.append(contentsOf: ["-e", "/bin/bash", "-c", command])

                case "xfce4-terminal":
                    if let workingDirectory = workingDirectory {
                        args.append(contentsOf: ["--working-directory=\(workingDirectory)"])
                    }
                    if let title = title {
                        args.append(contentsOf: ["--title=\(title)"])
                    }
                    args.append(contentsOf: ["-e", "/bin/bash -c '\(command)'"])

                case "xterm":
                    if let title = title {
                        args.append(contentsOf: ["-title", title])
                    }
                    args.append(contentsOf: ["-e", "/bin/bash", "-c"])

                    var cmd = command
                    if let workingDirectory = workingDirectory {
                        cmd = "cd '\(workingDirectory)' && \(command)"
                    }
                    args.append(cmd)

                default:
                    break
                }

                // Launch in background
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/\(terminal)")
                process.arguments = args
                try process.run()

                return
            } catch {
                // Terminal not found, try next one
                continue
            }
        }

        throw AutomationError.shellCommandFailed("No supported terminal emulator found. Install gnome-terminal, konsole, xfce4-terminal, or xterm.")
    }
    #endif
}
