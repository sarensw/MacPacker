//
//  ArchiveNameEncoding.swift
//  Modules
//

import Foundation

/// What an archive's names are written in, when the archive does not say.
///
/// A name is stored as bytes. A 7z or a RAR5 says what they mean, and so does a
/// zip that flags its names as UTF-8. Everything else leaves them in the code
/// page of the machine that wrote them, which is how a zip from a Chinese Windows
/// arrives in GBK with nothing in it to say so (#373).
public enum ArchiveNameEncoding: String, CaseIterable, Identifiable, Sendable {
    case utf8
    case gb18030
    case big5
    case shiftJIS
    case korean
    /// CP850, what a Western Windows writes. Its accented letters include those
    /// of CP437, the code page the zip format names, at the same bytes.
    case dosLatin
    case windowsLatin
    case dosCyrillic
    case windowsCyrillic

    public var id: Self { self }

    var stringEncoding: String.Encoding {
        func encoding(_ code: CFStringEncodings) -> String.Encoding {
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(code.rawValue)))
        }
        switch self {
        case .utf8: return .utf8
        case .gb18030: return encoding(.GB_18030_2000)
        case .big5: return encoding(.big5)
        case .shiftJIS: return encoding(.dosJapanese)
        case .korean: return encoding(.dosKorean)
        case .dosLatin: return encoding(.dosLatin1)
        case .windowsLatin: return .windowsCP1252
        case .dosCyrillic: return encoding(.dosRussian)
        case .windowsCyrillic: return .windowsCP1251
        }
    }

    /// The name macOS has for the encoding, in the user's language: the one
    /// Safari and TextEdit list.
    public var localizedName: String {
        String.localizedName(of: stringEncoding)
    }
}

// MARK: - Detection

extension ArchiveNameEncoding {
    /// These four decode almost any bytes, so only how the result reads tells
    /// them apart, which is what Foundation's detector goes by. Choosing among
    /// them it had 93 to 100 % of single file names right and every set of five,
    /// measured on 150 everyday names. Offered a Western or Cyrillic code page as
    /// well, it got worse at these and still took such names for one of them, so
    /// those go first, by `readsAsLatin` and `readsAsCyrillic`.
    private static let detectable: [ArchiveNameEncoding] = [.gb18030, .big5, .shiftJIS, .korean]

    /// More names tell nothing more, and Foundation takes a second per 6 MB.
    private static let detectionBytes = 1 << 16

    /// The encoding of `names`, which the archive declares none for, or `chosen`
    /// when the user picked one. `nil` when every name is UTF-8 as far as anyone
    /// can tell: then there is nothing to read differently.
    static func of(_ names: [Data], chosen: ArchiveNameEncoding?) -> ArchiveNameEncoding? {
        let legacy = names.filter { String(data: $0, encoding: .utf8) == nil }
        guard !legacy.isEmpty else { return nil }
        return chosen ?? detect(in: legacy)
    }

    /// Windows-1251 and the other code pages take a pick by hand: nothing tells
    /// their bytes from these reliably.
    static func detect(in names: [Data]) -> ArchiveNameEncoding {
        if names.allSatisfy(readsAsLatin) { return .dosLatin }
        if names.allSatisfy(readsAsCyrillic) { return .dosCyrillic }
        if holdsOnlyHangul(names) { return .korean }

        var text = Data()
        for name in names where text.count < detectionBytes {
            text.append(name)
            text.append(0x0A)
        }
        var converted: NSString?
        var lossy: ObjCBool = false
        let found = NSString.stringEncoding(
            for: text,
            encodingOptions: [
                .suggestedEncodingsKey: detectable.map(\.stringEncoding.rawValue),
                .useOnlySuggestedEncodingsKey: true
            ],
            convertedString: &converted,
            usedLossyConversion: &lossy)
        return detectable.first { $0.stringEncoding.rawValue == found } ?? .gb18030
    }

    /// Whether `names` stay in the bytes of the hangul in everyday use, the rows
    /// where GBK has its most common characters: Foundation takes a few short
    /// Korean names for Chinese. Chinese goes on to bytes up to 0xD7 within a few
    /// characters, so six that do not are Korean.
    private static func holdsOnlyHangul(_ names: [Data]) -> Bool {
        var characters = 0
        for name in names {
            var bytes = name.makeIterator()
            while let byte = bytes.next() {
                guard byte >= 0x80 else { continue }
                guard (0xB0...0xC8).contains(byte), let second = bytes.next(), (0xA1...0xFE).contains(second)
                else { return false }
                characters += 1
            }
        }
        return characters >= 6
    }

    private static func readsAsLatin(_ name: Data) -> Bool {
        reads(name, as: .dosLatin, alphabet: 0..<0x250, besideASCIILetters: true)
    }

    /// A Russian name has no use for a Latin letter inside a word. Kana do: a lead
    /// byte of `Г` with a second byte in ASCII.
    private static func readsAsCyrillic(_ name: Data) -> Bool {
        reads(name, as: .dosCyrillic, alphabet: 0x400..<0x530, besideASCIILetters: false)
    }

    /// Whether `name` reads as words in a single-byte code page: letters of
    /// `alphabet` where a word has them. A multibyte name fails on what its bytes
    /// come out as, box drawing and symbols. Katakana and some kanji are the
    /// exception, with a lead byte of `â` or `é` and a second byte in ASCII, but
    /// that byte puts a symbol or a capital right behind the letter.
    private static func reads(
        _ name: Data,
        as encoding: ArchiveNameEncoding,
        alphabet: Range<UInt32>,
        besideASCIILetters: Bool
    ) -> Bool {
        guard let text = String(data: name, encoding: encoding.stringEncoding) else { return false }
        let scalars = Array(text.unicodeScalars)
        return scalars.indices.allSatisfy { index in
            let scalar = scalars[index]
            guard !scalar.isASCII else { return true }
            guard scalar.properties.isAlphabetic, alphabet.contains(scalar.value) else { return false }
            guard index + 1 < scalars.count else { return true }
            let next = scalars[index + 1]
            return !(scalar.properties.isLowercase && next.properties.isUppercase)
                && !"@[\\]^`{|}~".unicodeScalars.contains(next)
                && (besideASCIILetters || !(next.isASCII && next.properties.isAlphabetic))
        }
    }
}

// MARK: - Reading a name

extension ArchiveNameEncoding {
    /// How a path reads in this encoding, one part at a time. A folder has to come
    /// out the same in every path that holds it, and read whole it does not: a
    /// byte can be left waiting for its second half at the `/`, so a path fails
    /// where the folder's own entry reads, and the folder shows twice. `/` itself
    /// is safe to split at, as no multibyte character here has one inside it.
    ///
    /// - Parameter stored: the path as it stands, which a part keeps when this
    ///   encoding has no reading for it.
    func read(_ bytes: Data, storedAs stored: String) -> String {
        zip(bytes.split(separator: 0x2F, omittingEmptySubsequences: false),
            stored.split(separator: "/", omittingEmptySubsequences: false))
            .map { read(part: $0) ?? String($1) }
            .joined(separator: "/")
    }

    /// How `bytes` read in this encoding, or `nil` to leave them as they are.
    ///
    /// A part that is not UTF-8 is in this encoding, or nothing can be done with
    /// it. One that is valid UTF-8 can be either. It is real UTF-8 when something
    /// that writes UTF-8 added it to the archive, and an accident when a short
    /// GBK name happens to fit, as 图片 does: it would stay ͼƬ, and the folder
    /// would show twice. Accidents come out as two-byte sequences, so as Greek or
    /// Cyrillic, while East Asian text in UTF-8 takes three.
    /// ponytail: a real Latin UTF-8 name in a GBK zip (Café) reads as GBK. Only a
    /// zip knows better, by its flag: 7-Zip has it in kpidCharacts, if that ever
    /// shows up in practice.
    private func read(part bytes: Data) -> String? {
        guard let decoded = String(data: bytes, encoding: stringEncoding) else { return nil }
        guard let utf8 = String(data: bytes, encoding: .utf8) else { return decoded }
        return !Self.isEastAsian(utf8) && Self.isEastAsian(decoded) ? decoded : nil
    }

    /// Kana, hangul and ideographs all sit above U+3000.
    private static func isEastAsian(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value >= 0x3000 }
    }
}
