import Foundation
// S2-0 harness shims: the device-state rules reference link enums that live in UI/CoreBluetooth files not compiled here.
extension DeviceLink { enum State: String { case off, idle, scanning, connecting, pairing, ready, unauthorized } }
enum BLESensors { enum Radio: String { case unknown, off, unauthorized, unsupported, on }; enum Link: String { case disconnected, connecting, connected } }
enum ConnStatus: Equatable { case green, red, amber, gray }
