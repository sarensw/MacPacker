//
//  SystemHelper.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 28.07.25.
//

import AppKit

final class SystemHelper {
    @MainActor static let shared = SystemHelper()
    
    private init() {}
    
    func format(bytes: Int) -> String {
        return format(bytes: Int64(bytes))
    }
    
    /// Takes in bytes and formats it to a human readible string (e.g. 512000 > 512 KB). It returns
    /// an empty string in case the number of bytes is less than 0. This can happen for folder
    /// or special entries (e.g. parent entry "..")
    /// - Parameter bytes: Number of bytes
    /// - Returns: Human readable string
    func format(bytes: Int64) -> String {
        guard bytes >= 0 else {
            return ""
        }

        // Adapted from http://stackoverflow.com/a/18650828
        let suffixes = ["bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]
        let k: Double = 1000
        let bytesAsDouble = Double(bytes) // Convert Int64 to Double for calculations
        let i = bytesAsDouble == 0 ? 0 : floor(log(bytesAsDouble) / log(k))

        // Format number with thousands separator and everything below 1 GB with no decimal places.
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = i < 3 ? 0 : 1
        numberFormatter.numberStyle = .decimal

        let numberString = numberFormatter.string(from: NSNumber(value: bytesAsDouble / pow(k, i))) ?? "Unknown"
        let suffix = suffixes[Int(i)]
        return "\(numberString) \(suffix)"
    }
    
    func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
            // Use relative terms
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .full  // "Today" / "Yesterday"
            let relativePart = relativeFormatter.localizedString(for: date, relativeTo: Date())
            
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            let timePart = timeFormatter.string(from: date)
            
            return "\(relativePart), \(timePart)"
        }
        
        // Fallback to standard localized date+time (like Finder does)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        return formatter.string(from: date)
    }
    
    func formatPosixPermissions(_ permissions: Int) -> String {
        let m = mode_t(permissions) // normalize to mode_t

        var result = ""

        // File type
        switch m & S_IFMT {
        case S_IFDIR:  result.append("d")   // directory
        case S_IFREG:  result.append("-")   // regular file
        case S_IFLNK:  result.append("l")   // symlink
        case S_IFCHR:  result.append("c")   // char device
        case S_IFBLK:  result.append("b")   // block device
        case S_IFIFO:  result.append("p")   // FIFO / pipe
        case S_IFSOCK: result.append("s")   // socket
        default:       result.append("-")
        }

        // Permissions
        let permissions: [(mode_t, String)] = [
            (S_IRUSR, "r"), (S_IWUSR, "w"), (S_IXUSR, "x"),
            (S_IRGRP, "r"), (S_IWGRP, "w"), (S_IXGRP, "x"),
            (S_IROTH, "r"), (S_IWOTH, "w"), (S_IXOTH, "x")
        ]

        for (bit, char) in permissions {
            result.append((m & bit) != 0 ? char : "-")
        }

        return result
    }
}

