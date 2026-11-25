//
//  EntryText.swift
//  Modules
//
//  The text in an entry's cells, the same in the archive window and in Quick
//  Look.
//

import Foundation

/// How the archive window and the Quick Look preview write an entry's size,
/// date and permissions. One formatter for both, so an entry reads the same in
/// each: before, the preview left a file of zero bytes empty where the window
/// said "0 bytes" (#251 B11).
public enum EntryText {
    /// The size of a file, or of an archive inside the archive. A folder has
    /// none of its own to show, and neither has the `..` row.
    public static func size(of item: ArchiveItem, packed: Bool) -> String {
        guard item.type == .file || item.type == .archive else { return "" }
        return size(packed ? item.compressedSize : item.uncompressedSize)
    }

    /// `512000` reads "512 KB": steps of 1000, as Finder counts, without
    /// decimals below a gigabyte. Zero reads "0 bytes"; less than zero, nothing.
    public static func size(_ bytes: Int) -> String {
        size(Int64(bytes))
    }

    public static func size(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "" }

        let suffixes = ["bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]
        let k: Double = 1000
        let value = Double(bytes)
        let exponent = value == 0 ? 0 : floor(log(value) / log(k))

        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = exponent < 3 ? 0 : 1
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: value / pow(k, exponent))) ?? "Unknown"
        return "\(number) \(suffixes[Int(exponent)])"
    }

    /// Today and yesterday by name with the time, as Finder writes them; any
    /// other day as a medium date with a short time. By the calendar day: an
    /// entry from shortly before midnight is yesterday's, not "10 minutes ago".
    public static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    /// As `ls -l` writes them: the kind of entry, then read, write and execute
    /// for the owner, the group and everyone else, `-rw-r--r--`.
    public static func permissions(_ mode: Int) -> String {
        let m = mode_t(mode)
        var result = ""
        switch m & S_IFMT {
        case S_IFDIR: result.append("d")
        case S_IFLNK: result.append("l")
        case S_IFCHR: result.append("c")
        case S_IFBLK: result.append("b")
        case S_IFIFO: result.append("p")
        case S_IFSOCK: result.append("s")
        default: result.append("-")
        }
        let bits: [(mode_t, Character)] = [
            (S_IRUSR, "r"), (S_IWUSR, "w"), (S_IXUSR, "x"),
            (S_IRGRP, "r"), (S_IWGRP, "w"), (S_IXGRP, "x"),
            (S_IROTH, "r"), (S_IWOTH, "w"), (S_IXOTH, "x"),
        ]
        for (bit, char) in bits {
            result.append(m & bit != 0 ? char : "-")
        }
        return result
    }
}
