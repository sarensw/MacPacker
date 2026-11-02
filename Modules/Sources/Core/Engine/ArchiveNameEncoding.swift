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
    /// CP950, Big5 as Windows writes it: the standard has no 恒 and no 碁.
    case big5
    case shiftJIS
    case korean
    /// CP850, what a Western Windows writes. Its accented letters include those
    /// of CP437, the code page the zip format names, at the same bytes.
    case dosLatin
    case windowsLatin
    /// What a classic Mac writes. See `western` on `of(_:chosen:western:)`.
    case macRoman
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
        case .big5: return encoding(.dosChineseTrad)
        case .shiftJIS: return encoding(.dosJapanese)
        case .korean: return encoding(.dosKorean)
        case .dosLatin: return encoding(.dosLatin1)
        case .windowsLatin: return .windowsCP1252
        case .macRoman: return .macOSRoman
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

    /// Not letters, but everyday in a name: `Приказ №15`, `§ 34`, `20°`.
    private static let symbolsInNames = "№°§".unicodeScalars

    /// The encoding of `names`, which the archive declares none for, or `chosen`
    /// when the user picked one. `nil` when every name is UTF-8 as far as anyone
    /// can tell: then there is nothing to read differently.
    ///
    /// - Parameter western: what the format at hand writes Western names in. Every
    ///   byte is a letter in CP850 and in Mac Roman alike (0x8E is `Ä` and `é`), so
    ///   the format is all that tells them apart.
    static func of(
        _ names: [Data],
        chosen: ArchiveNameEncoding?,
        western: ArchiveNameEncoding = .dosLatin
    ) -> ArchiveNameEncoding? {
        let legacy = names.filter { String(data: $0, encoding: .utf8) == nil }
        guard !legacy.isEmpty else { return nil }
        return chosen ?? detect(in: legacy, western: western)
    }

    /// Windows-1251 and the other code pages take a pick by hand: nothing tells
    /// their bytes from these reliably.
    static func detect(in names: [Data], western: ArchiveNameEncoding = .dosLatin) -> ArchiveNameEncoding {
        if names.allSatisfy({ reads($0, asLatin: western) }) { return western }
        if names.allSatisfy(readsAsCyrillic) { return .dosCyrillic }

        var text = Data()
        for name in names where text.count < detectionBytes {
            text.append(name)
            text.append(0x0A)
        }
        if holdsOnlyHangul(names), !readsAsChineseWords(text) { return .korean }

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

    /// Whether `text` reads as words in Chinese. Foundation's word breaks know the
    /// language: an everyday name comes apart into words of two characters and
    /// more, while hangul taken for GBK make up single characters that form none.
    private static func readsAsChineseWords(_ text: Data) -> Bool {
        guard let chinese = String(data: text, encoding: gb18030.stringEncoding) else { return false }
        var characters = 0
        var inWords = 0
        chinese.enumerateSubstrings(in: chinese.startIndex..., options: .byWords) { word, _, _, _ in
            guard let word, isEastAsian(word) else { return }
            characters += word.count
            if word.count > 1 { inWords += word.count }
        }
        return inWords * 2 >= characters
    }

    private static func reads(_ name: Data, asLatin encoding: ArchiveNameEncoding) -> Bool {
        reads(name, as: encoding, alphabet: 0..<0x250, besideASCIILetters: true)
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
            guard !scalar.isASCII, !symbolsInNames.contains(scalar) else { return true }
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
    /// What happens to a part of a name that is valid UTF-8, which it can be in
    /// this encoding too.
    enum ValidUTF8: Sendable {
        /// It is read in this encoding, as the user picked it for what the archive
        /// does not declare.
        case read
        /// It is read in this encoding if it only looks like UTF-8 by accident: a
        /// short GBK name can fit, as 图片 does, and would stay ͼƬ with the folder
        /// showing twice. Accidents come out as two-byte sequences, so as Greek or
        /// Cyrillic, while East Asian text in UTF-8 takes three.
        case readIfAccident
        /// It stays: this is UTF-8, and what is not was added by something else.
        case left
    }

    /// Looking at this many names tells as much as looking at them all.
    private static let namesToCompare = 1 << 12

    /// What to make of the parts of `names` that are valid UTF-8, left to
    /// detection. One name in Latin-1 among UTF-8 must not make accidents of the
    /// others, as `Müller` in GBK is `M眉ller`. By parts, as one folder repeats in
    /// every path below it, and a tie goes to the accident: in a small GBK archive
    /// `图片/风景.txt` is one of each.
    static func validUTF8(in names: [Data]) -> ValidUTF8 {
        let parts = Set(names.prefix(namesToCompare)
            .flatMap { $0.split(separator: 0x2F) }
            .filter { $0.contains { $0 >= 0x80 } })
        let valid = parts.count { String(data: $0, encoding: .utf8) != nil }
        return valid > parts.count - valid ? .left : .readIfAccident
    }

    /// How a path reads in this encoding, one part at a time. A folder has to come
    /// out the same in every path that holds it, and read whole it does not: a
    /// byte can be left waiting for its second half at the `/`, so a path fails
    /// where the folder's own entry reads, and the folder shows twice. `/` itself
    /// is safe to split at, as no multibyte character here has one inside it.
    ///
    /// By scalars: `/` and a combining mark are one `Character`, which is what the
    /// bytes of 通 (CD A8) stand for in UTF-8, and that slash would go unseen.
    ///
    /// - Parameters:
    ///   - stored: the path as it stands, which a part keeps when this encoding
    ///     has no reading for it.
    ///   - slashesWereBackslashes: see `SevenZipArchive.slashesWereBackslashes`.
    func read(
        _ bytes: Data,
        storedAs stored: String,
        validUTF8: ValidUTF8,
        slashesWereBackslashes: Bool = false
    ) -> String {
        var parts = zip(bytes.split(separator: 0x2F, omittingEmptySubsequences: false),
                        stored.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false))
            .map { Part(bytes: $0, stored: String($1)) }
        if slashesWereBackslashes {
            parts = joinedAtSecondBytes(parts)
        }
        return parts
            .map { read(part: $0.bytes, validUTF8: validUTF8) ?? $0.stored }
            .joined(separator: "/")
    }

    private struct Part {
        var bytes: Data
        var stored: String
    }

    /// Puts together what a `/` split that was the second byte of a character:
    /// such a part does not decode until it has the rest of the character. A part
    /// that still does not at the end of the path stays as it was, as nothing
    /// makes a character of it.
    private func joinedAtSecondBytes(_ parts: [Part]) -> [Part] {
        var joined: [Part] = []
        var index = 0
        while index < parts.count {
            var part = parts[index]
            var last = index
            while !decodes(part.bytes), last + 1 < parts.count {
                last += 1
                part = Part(bytes: part.bytes + [0x5C] + parts[last].bytes,
                            stored: part.stored + "\\" + parts[last].stored)
            }
            guard decodes(part.bytes) else {
                joined.append(parts[index])
                index += 1
                continue
            }
            joined.append(part)
            index = last + 1
        }
        return joined
    }

    private func decodes(_ bytes: Data) -> Bool {
        String(data: bytes, encoding: stringEncoding) != nil
    }

    /// How `bytes` read in this encoding, or `nil` to leave them as they are.
    ///
    /// ponytail: with no flag to go by, a real Latin UTF-8 name beside as much GBK
    /// (Café in a tar) reads as GBK, and a CP866 сон stays UTF-8 until picked. The
    /// bytes do not tell, and a wrong guess here would break what reads right.
    private func read(part bytes: Data, validUTF8: ValidUTF8) -> String? {
        guard let decoded = String(data: bytes, encoding: stringEncoding) else { return nil }
        guard let utf8 = String(data: bytes, encoding: .utf8) else { return decoded }
        switch validUTF8 {
        case .read: return decoded
        case .readIfAccident: return !Self.isEastAsian(utf8) && Self.isEastAsian(decoded) ? decoded : nil
        case .left: return nil
        }
    }

    /// Kana, hangul and ideographs all sit above U+3000.
    private static func isEastAsian(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value >= 0x3000 }
    }
}
