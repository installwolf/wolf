import Foundation

/// Filesystem locations. All overridable via environment so the tool can be
/// smoke-tested in a sandbox without touching the real system files.
public enum Paths {
    static func env(_ key: String, _ fallback: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? fallback
    }

    /// Root-owned state directory.
    public static var home: String { env("WOLF_HOME", "/Library/Application Support/Wolf") }
    public static var stateFile: String { home + "/state.json" }
    public static var clockFloorFile: String { home + "/clock_floor" }

    /// System files we manage.
    public static var hosts: String { env("WOLF_HOSTS", "/etc/hosts") }
    public static var pfAnchor: String { env("WOLF_PF_ANCHOR", "/etc/pf.anchors/wolf") }
    public static var daemonPlist: String {
        env("WOLF_PLIST", "/Library/LaunchDaemons/com.wolf.daemon.plist")
    }

    /// Files that get the immutable (schg) flag once enforcement is live.
    public static var immutableTargets: [String] { [stateFile, hosts, pfAnchor, daemonPlist] }
}
