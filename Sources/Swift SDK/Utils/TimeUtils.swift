import Foundation

class TimeUtils {
    static func currentTimestampInSeconds() -> Int {
        return Int(Date().timeIntervalSince1970)
    }
    
    static func currentTimestampInSecondsString() -> String {
        return String(currentTimestampInSeconds())
    }
}
