package com.rashed.bikesensordoctor.ble

import java.util.UUID

/**
 * Known UUIDs. Standard ones come from the Bluetooth SIG Assigned Numbers.
 * The XDS/Branta entries are from community open-source bridge projects (see docs/PHASE2_PROTOCOL_RESEARCH.md);
 * they are NOT manufacturer documentation and are labelled as such wherever shown to the user.
 */
object Uuids {
    private const val BASE = "0000%04x-0000-1000-8000-00805f9b34fb"
    fun sig(short: Int): UUID = UUID.fromString(String.format(BASE, short))

    // Services
    val GENERIC_ACCESS: UUID = sig(0x1800)
    val GENERIC_ATTRIBUTE: UUID = sig(0x1801)
    val DEVICE_INFORMATION: UUID = sig(0x180A)
    val BATTERY: UUID = sig(0x180F)
    val CYCLING_SPEED_CADENCE: UUID = sig(0x1816)
    val CYCLING_POWER: UUID = sig(0x1818)
    val MESH_PROXY: UUID = sig(0x1828)
    val MESH_PROVISIONING: UUID = sig(0x1827)

    // Characteristics
    val DEVICE_NAME: UUID = sig(0x2A00)
    val APPEARANCE: UUID = sig(0x2A01)
    val BATTERY_LEVEL: UUID = sig(0x2A19)
    val MODEL_NUMBER: UUID = sig(0x2A24)
    val SERIAL_NUMBER: UUID = sig(0x2A25)
    val FIRMWARE_REV: UUID = sig(0x2A26)
    val HARDWARE_REV: UUID = sig(0x2A27)
    val SOFTWARE_REV: UUID = sig(0x2A28)
    val MANUFACTURER_NAME: UUID = sig(0x2A29)
    val CSC_MEASUREMENT: UUID = sig(0x2A5B)
    val CSC_FEATURE: UUID = sig(0x2A5C)
    val SENSOR_LOCATION: UUID = sig(0x2A5D)
    val SC_CONTROL_POINT: UUID = sig(0x2A55)
    val CP_MEASUREMENT: UUID = sig(0x2A63)
    val CP_VECTOR: UUID = sig(0x2A64)
    val CP_FEATURE: UUID = sig(0x2A65)
    val CP_CONTROL_POINT: UUID = sig(0x2A66)
    val MESH_PROXY_DATA_IN: UUID = sig(0x2ADD)
    val MESH_PROXY_DATA_OUT: UUID = sig(0x2ADE)

    // Descriptor
    val CCCD: UUID = sig(0x2902)

    // Custom services seen on the user's XDS-A001 device (origin unknown; no public documentation found)
    val XDS_CUSTOM_0401: UUID = UUID.fromString("a6ed0401-d344-460a-8075-b9e8ec90d71b")
    val XDS_CUSTOM_0201: UUID = UUID.fromString("a6ed0201-d344-460a-8075-b9e8ec90d71b")
    val XDS_CUSTOM_0402: UUID = UUID.fromString("a6ed0402-d344-460a-8075-b9e8ec90d71b")
    val XDS_CUSTOM_0202: UUID = UUID.fromString("a6ed0202-d344-460a-8075-b9e8ec90d71b")

    private val names: Map<UUID, String> = mapOf(
        GENERIC_ACCESS to "Generic Access",
        GENERIC_ATTRIBUTE to "Generic Attribute",
        DEVICE_INFORMATION to "Device Information",
        BATTERY to "Battery Service",
        CYCLING_SPEED_CADENCE to "Cycling Speed & Cadence (0x1816)",
        CYCLING_POWER to "Cycling Power (0x1818)",
        MESH_PROXY to "Mesh Proxy (0x1828) — used by XDS as its power service per community bridges",
        MESH_PROVISIONING to "Mesh Provisioning (0x1827)",
        DEVICE_NAME to "Device Name",
        APPEARANCE to "Appearance",
        BATTERY_LEVEL to "Battery Level",
        MODEL_NUMBER to "Model Number",
        SERIAL_NUMBER to "Serial Number",
        FIRMWARE_REV to "Firmware Revision",
        HARDWARE_REV to "Hardware Revision",
        SOFTWARE_REV to "Software Revision",
        MANUFACTURER_NAME to "Manufacturer Name",
        CSC_MEASUREMENT to "CSC Measurement",
        CSC_FEATURE to "CSC Feature",
        SENSOR_LOCATION to "Sensor Location",
        SC_CONTROL_POINT to "SC Control Point (0x2A55)",
        CP_MEASUREMENT to "Cycling Power Measurement (0x2A63)",
        CP_VECTOR to "Cycling Power Vector",
        CP_FEATURE to "Cycling Power Feature",
        CP_CONTROL_POINT to "Cycling Power Control Point",
        MESH_PROXY_DATA_IN to "Mesh Proxy Data In",
        MESH_PROXY_DATA_OUT to "Mesh Proxy Data Out",
        CCCD to "Client Characteristic Configuration",
        XDS_CUSTOM_0401 to "XDS custom service 0401 (undocumented)",
        XDS_CUSTOM_0201 to "XDS custom service 0201 (undocumented)",
        XDS_CUSTOM_0402 to "XDS custom characteristic 0402 (undocumented, notify)",
        XDS_CUSTOM_0202 to "XDS custom characteristic 0202 (undocumented, notify)",
    )

    fun name(uuid: UUID): String = names[uuid] ?: "Unknown"

    /** Short display form: 16-bit for SIG UUIDs, full for custom. */
    fun short(uuid: UUID): String {
        val s = uuid.toString()
        return if (s.startsWith("0000") && s.endsWith("-0000-1000-8000-00805f9b34fb"))
            "0x" + s.substring(4, 8).uppercase()
        else s
    }
}
