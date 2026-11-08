import Foundation

/// Corre AppleScript en una cola serial propia, fuera del hilo principal:
/// un Music colgado o el diálogo de permisos no pueden congelar el player.
final class AppleScriptRunner {
    static let shared = AppleScriptRunner()

    let queue = DispatchQueue(label: "musicfy.applescript", qos: .userInitiated)

    /// Sólo se toca desde `queue`.
    private var compiled: [String: NSAppleScript] = [:]

    struct Failure: Error {
        let number: Int
        let message: String

        /// errAEEventNotPermitted: el usuario no dio (o negó) el permiso de Automatización.
        var isNotAuthorized: Bool { number == -1743 }
    }

    /// Compila sin ejecutar. Sirve para saber si una variante del script es válida
    /// en la versión de Music instalada (por ejemplo `favorited` contra `loved`).
    func compiles(_ source: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        if compiled[source] != nil { return true }
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { return false }
        compiled[source] = script
        return true
    }

    /// Ejecuta en la cola de AppleScript. `cache: false` para scripts con valores
    /// interpolados (posición, volumen), que no vale la pena guardar compilados.
    func run(_ source: String, cache: Bool = true) -> Result<NSAppleEventDescriptor, Failure> {
        dispatchPrecondition(condition: .onQueue(queue))
        let script: NSAppleScript
        if cache, let hit = compiled[source] {
            script = hit
        } else {
            guard let fresh = NSAppleScript(source: source) else {
                return .failure(Failure(number: 0, message: "No se pudo crear el script"))
            }
            var error: NSDictionary?
            guard fresh.compileAndReturnError(&error) else {
                return .failure(Self.failure(from: error))
            }
            if cache { compiled[source] = fresh }
            script = fresh
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { return .failure(Self.failure(from: error)) }
        return .success(result)
    }

    /// Atajo para comandos sin respuesta: se encolan y listo.
    func fire(_ source: String, cache: Bool = true, then completion: (() -> Void)? = nil) {
        queue.async {
            _ = self.run(source, cache: cache)
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    private static func failure(from info: NSDictionary?) -> Failure {
        let number = (info?[NSAppleScript.errorNumber] as? Int) ?? 0
        let message = (info?[NSAppleScript.errorMessage] as? String) ?? "Error de AppleScript"
        return Failure(number: number, message: message)
    }
}

extension NSAppleEventDescriptor {
    /// Ítem de una lista de AppleScript (que empieza en 1), tolerante a `missing value`.
    func item(_ index: Int) -> NSAppleEventDescriptor? {
        guard index <= numberOfItems else { return nil }
        let item = atIndex(index)
        if item?.descriptorType == DescType(0x6E75_6C6C) { return nil } // 'null'
        if item?.descriptorType == DescType(0x6D73_6E67) { return nil } // 'msng' = missing value
        return item
    }

    func string(_ index: Int) -> String { item(index)?.stringValue ?? "" }
    func double(_ index: Int) -> Double { item(index)?.doubleValue ?? 0 }
    func int(_ index: Int) -> Int { Int(item(index)?.int32Value ?? 0) }
    func bool(_ index: Int) -> Bool { item(index)?.booleanValue ?? false }
}
