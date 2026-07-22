import Foundation

/// Idempotent wiring of the Wolf anchor into `/etc/pf.conf`, so the pf rules
/// that block DoH/DoT survive a reboot. Pure string logic; the caller does the
/// privileged read/write.
public enum PfConf {
    /// Returns pf.conf content with the Wolf anchor appended, or `nil` if the
    /// anchor is already referenced (so the caller writes nothing).
    public static func wire(into existing: String, anchorPath: String) -> String? {
        // Detect any prior `anchor "wolf"` regardless of surrounding whitespace.
        let alreadyWired = existing
            .split(separator: "\n")
            .contains { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return t.hasPrefix("anchor") && t.contains("\"wolf\"")
            }
        guard !alreadyWired else { return nil }

        var out = existing
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        out += """

        # --- Wolf: DoH/DoT bypass block. Managed by `wolf`; do not edit. ---
        anchor "wolf"
        load anchor "wolf" from "\(anchorPath)"

        """
        return out
    }
}

/// Renders the root LaunchDaemon plist that keeps `wolfd` alive. Generated at
/// bootstrap time so it points at wherever bootstrap copied the daemon binary.
public enum DaemonPlist {
    public static let label = "com.wolf.daemon"

    public static func render(wolfdPath: String, logPath: String = "/var/log/wolf.log") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>

            <key>ProgramArguments</key>
            <array>
                <string>\(wolfdPath)</string>
            </array>

            <!-- Start at boot and relaunch if killed: the watchdog must be hard to stop. -->
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>

            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logPath)</string>

            <key>ProcessType</key>
            <string>Background</string>
        </dict>
        </plist>
        """
    }
}
