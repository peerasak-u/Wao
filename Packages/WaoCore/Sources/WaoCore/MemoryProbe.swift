import Darwin
import Foundation

public enum MemoryProbe {
    /// `os_proc_available_memory()`: how much more this process may allocate before jetsam. iOS devices only;
    /// `nil` elsewhere (the simulator and macOS have no such limit).
    public static func availableBytes() -> UInt64? {
        #if os(iOS) && !targetEnvironment(simulator)
        return UInt64(os_proc_available_memory())
        #else
        return nil
        #endif
    }

    /// Physical footprint, the number jetsam compares against the limit.
    public static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
