import Foundation
import IOKit

public enum TouchBarHardwareCapability {
    private static let namePrefixes = ["touch-bar", "dfr-drv", "dispdfr", "backlight-dfr"]
    private static let deviceTypeValues = ["touch-bar", "displaydfr-subsystem", "lcddfr"]
    private static let productValues = ["touchbaruserdevice"]

    public static var isAvailable: Bool {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { return false }
            defer { IOObjectRelease(entry) }

            if matchesTouchBarMarker(entry) {
                return true
            }
        }
    }

    private static func matchesTouchBarMarker(_ entry: io_registry_entry_t) -> Bool {
        let name = registryName(for: entry)
        if namePrefixes.contains(where: { name.hasPrefix($0) }) {
            return true
        }

        let deviceType = registryStringProperty("device_type", for: entry)
        if deviceTypeValues.contains(deviceType) {
            return true
        }

        let product = registryStringProperty("Product", for: entry)
        return productValues.contains(product)
    }

    private static func registryName(for entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return "" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).lowercased()
    }

    private static func registryStringProperty(_ key: String, for entry: io_registry_entry_t) -> String {
        guard let value = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return ""
        }
        return value.lowercased()
    }
}
