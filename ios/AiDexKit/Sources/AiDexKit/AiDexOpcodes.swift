// AiDexOpcodes.swift — ported 1:1 from
// Common/src/main/java/tk/glucodata/drivers/aidex/native/protocol/AiDexOpcodes.kt

public enum AiDexOpcodes {

    // -- F002 Wire Opcodes --
    public static let GET_STARTUP_DEVICE_INFO = 0x10
    public static let POST_BOND_CONFIG = GET_STARTUP_DEVICE_INFO
    public static let GET_BROADCAST_DATA = 0x11
    public static let SET_NEW_SENSOR = 0x20
    public static let GET_LOCAL_START_TIME = 0x21
    public static let GET_START_TIME = GET_LOCAL_START_TIME
    public static let GET_HISTORY_RANGE = 0x22
    public static let GET_HISTORIES_RAW = 0x23
    public static let GET_HISTORIES = 0x24
    public static let SET_CALIBRATION = 0x25
    public static let GET_CALIBRATION_RANGE = 0x26
    public static let GET_CALIBRATION = 0x27
    public static let SET_DEFAULT_PARAM = 0x30
    public static let GET_DEFAULT_PARAM = 0x31
    public static let GET_SENSOR_CHECK = 0x32
    public static let GET_AUTO_UPDATE_STATUS = 0x33
    public static let SET_AUTO_UPDATE_STATUS = 0x34
    public static let SET_DYNAMIC_ADV_MODE = 0x35
    public static let DELETE_BOND = 0xF2
    public static let RESET = 0xF0
    public static let SHELF_MODE = 0xF1
    public static let CLEAR_STORAGE = 0xF3

    // -- F003 Frame Constants --
    public static let DATA_FRAME_LENGTH = 17
    public static let STATUS_FRAME_LENGTH = 5
    public static let GLUCOSE_MASK = 0x03FF
    public static let MAX_VALID_GLUCOSE = 500
    public static let MIN_VALID_GLUCOSE = 20
    public static let SENTINEL_GLUCOSE = 1023

    // -- F003 Opcode Scaling --
    public static let DIRECT_OPCODES: Set<Int> = [0xA1, 0xA4, 0x5B, 0xD7]
    public static let HALF_SCALE_OPCODES: Set<Int> = [0xD2]

    public static func scalingFactor(_ opcode: Int) -> Float? {
        if DIRECT_OPCODES.contains(opcode) { return 1.0 }
        if HALF_SCALE_OPCODES.contains(opcode) { return 0.5 }
        return nil
    }

    // -- History Row Sizes --
    public static let HISTORY_RAW_ROW_SIZE = 2
    public static let HISTORY_BRIEF_ROW_SIZE = 5
    public static let CALIBRATION_ROW_SIZE = 8

    // -- Advertisement --
    public static let COMPANY_ID = 0x0059
    public static let KNOWN_NAME_PREFIXES = ["AiDex", "AiDEX", "AIDEX", "Linx", "LINX", "CGM"]

    public static func isAiDexDevice(_ name: String?) -> Bool {
        guard let name else { return false }
        return KNOWN_NAME_PREFIXES.contains { name.hasPrefix($0) }
    }
}
