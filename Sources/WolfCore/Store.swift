import Foundation

/// Loads and persists `WolfState`. Persisting transparently clears the
/// immutable flag, writes, and re-applies it, so callers don't juggle chflags.
public struct Store {
    public init() {}

    public func load() throws -> WolfState {
        let path = Paths.stateFile
        guard FileManager.default.fileExists(atPath: path) else { return WolfState() }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(WolfState.self, from: data)
    }

    public func save(_ state: WolfState) throws {
        let dir = Paths.home
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(state)

        Enforcer.setImmutable(false, path: Paths.stateFile)
        do {
            try data.write(to: URL(fileURLWithPath: Paths.stateFile), options: .atomic)
        } catch {
            throw WolfError.io("could not write state (need root?): \(error.localizedDescription)")
        }
        Enforcer.setImmutable(true, path: Paths.stateFile)
    }
}
