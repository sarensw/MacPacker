//
//  PasswordTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 29.07.26.
//

import Testing
import Foundation
@testable import Core

// MARK: - Helpers

/// Resolver that hands out `answers` in order and then cancels.
///
/// Cancelling once the answers run out is the point: an engine retry loop that
/// ignores a wrong password would otherwise spin forever, and a hung test is
/// much harder to read than a failed one.
private actor PasswordAnswers {
    private var remaining: [String]
    private let repeatsLast: Bool
    /// `attempt` of every request seen, in order.
    private(set) var attempts: [Int] = []

    init(_ answers: String...) {
        self.remaining = answers
        self.repeatsLast = false
    }

    /// Answers with the same password every time. Safe only for a password that
    /// actually works — listing and extracting each open the archive, so a
    /// bounded list would run dry halfway through a test.
    static func always(_ password: String) -> PasswordAnswers {
        PasswordAnswers(password, repeatsLast: true)
    }

    private init(_ password: String, repeatsLast: Bool) {
        self.remaining = [password]
        self.repeatsLast = repeatsLast
    }

    private func next(attempt: Int) -> String? {
        attempts.append(attempt)
        if repeatsLast { return remaining.first }
        return remaining.isEmpty ? nil : remaining.removeFirst()
    }

    nonisolated var resolver: ArchivePasswordResolver {
        { [self] request in await next(attempt: request.attempt) }
    }

    var callCount: Int { attempts.count }
}

/// Resolver that never answers — extraction must fail, not stall.
private let neverResolves: ArchivePasswordResolver = { _ in nil }

// Every fixture packs `TestArchives/defaultArchiveContent`, so a correct
// decryption has to reproduce those files byte for byte.

/// The text entry, with a space in the name.
private let helloPath = "hello world.txt"
private let helloContents = "Hello World!\n"
/// `zip_mixed.zip` leaves everything under `folder/` unencrypted.
private let plainPath = "folder/README.md"
/// Every file of the payload, as archive-relative paths. `NestedArchive.zip` is
/// 52 KB of binary, which is the interesting one: a truncated or wrongly
/// decrypted stream shows up here and not in a 13-byte text file.
private let payloadFiles = ["hello world.txt", "folder/README.md", "folder/NestedArchive.zip"]

/// The original file the archives were built from.
private func payloadSource(_ path: String) -> URL {
    Bundle.module.url(forResource: "defaultArchiveContent", withExtension: nil)!
        .appendingPathComponent(path)
}

/// True when an extracted file is byte-identical to the payload source.
private func matchesPayload(_ extracted: URL, _ path: String) -> Bool {
    guard let got = try? Data(contentsOf: extracted),
          let want = try? Data(contentsOf: payloadSource(path))
    else { return false }
    return got == want
}

private let correctPassword = "password"
private let unicodePassword = "pässwörd"
private let symbolPassword = "p@ss w'ord\"$x"
private let longPassword = String(repeating: "a", count: 200)

private func fixture(_ name: String) -> URL {
    let folder = Bundle.module.url(forResource: "password", withExtension: nil)!
    return folder.appendingPathComponent(name)
}

private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasswordTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Reads back an extracted file. Returns nil when it is missing.
private func contents(of url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
}

private func engines() -> [(name: String, engine: any ArchiveEngine)] {
    [("7zip", Archive7ZipEngine()), ("xad", ArchiveXadEngine())]
}

/// True once the RAR fixtures have been committed. They can only be built on a
/// machine with `rar`, so the RAR suite skips rather than fails until then.
private var rarFixturesAvailable: Bool {
    FileManager.default.fileExists(atPath: fixture("rar5_aes.rar").path)
}

extension AllCoreTests {

    // MARK: - Correct password produces real contents

    /// The bug the customer hit: 7-Zip reported success but wrote 0-byte files.
    /// Every one of these asserts the *contents*, never just `fileExists`.
    @MainActor struct PasswordExtractionTests {

        /// Every encrypted zip/7z variant, both engines, single-item extraction.
        @Test(arguments: [
            ("zip_zipcrypto.zip", correctPassword),
            ("zip_aes256.zip", correctPassword),
            ("zip_aes128.zip", correctPassword),
            ("zip_mixed.zip", correctPassword),
            ("zip_unicode_pw.zip", unicodePassword),
            ("zip_symbol_pw.zip", symbolPassword),
            ("zip_long_pw.zip", longPassword),
            ("7z_aes256.7z", correctPassword),
            ("7z_encrypted_header.7z", correctPassword),
            ("7z_symbol_pw.7z", symbolPassword)
        ])
        func extractsEncryptedEntryWithCorrectPassword(name: String, password: String) async throws {
            for (engineName, engine) in engines() {
                // XAD cannot open a header-encrypted archive: the header has to be
                // decrypted during init and XADArchive only accepts a password
                // afterwards. Covered by xadCannotOpenHeaderEncryptedArchives.
                if engineName == "xad" && name.contains("encrypted_header") { continue }

                let answers = PasswordAnswers.always(password)
                let url = fixture(name)
                let destination = try tempDirectory()
                defer { try? FileManager.default.removeItem(at: destination) }

                let load = try await engine.loadArchive(url: url, passwordResolver: answers.resolver)
                let hello = try #require(
                    load.items.values.first { $0.virtualPath == helloPath },
                    "\(engineName)/\(name): \(helloPath) missing from listing"
                )

                let result = try await engine.extract(
                    items: [hello],
                    from: url,
                    to: destination,
                    passwordResolver: answers.resolver
                )

                let extracted = try #require(result[hello], "\(engineName)/\(name): no url returned")
                #expect(
                    contents(of: extracted) == helloContents,
                    "\(engineName)/\(name): extracted contents wrong or file empty"
                )
            }
        }

        /// Whole-archive extraction, the "Extract here" path.
        @Test(arguments: ["zip_zipcrypto.zip", "zip_aes256.zip", "7z_aes256.7z"])
        func extractsWholeArchiveWithCorrectPassword(name: String) async throws {
            for (engineName, engine) in engines() {
                // XAD cannot open a header-encrypted archive: the header has to be
                // decrypted during init and XADArchive only accepts a password
                // afterwards. Covered by xadCannotOpenHeaderEncryptedArchives.
                if engineName == "xad" && name.contains("encrypted_header") { continue }

                let answers = PasswordAnswers.always(correctPassword)
                let destination = try tempDirectory()
                defer { try? FileManager.default.removeItem(at: destination) }

                try await engine.extract(
                    fixture(name),
                    to: destination,
                    passwordResolver: answers.resolver
                )

                for path in payloadFiles {
                    #expect(
                        matchesPayload(destination.appendingPathComponent(path), path),
                        "\(engineName)/\(name): \(path) wrong, empty or missing"
                    )
                }
            }
        }

        /// Multiple encrypted entries in one call — 7-Zip extracts them in a
        /// single pass, so a per-entry password failure must not be swallowed.
        @Test func extractsMultipleEncryptedEntriesAtOnce() async throws {
            for (engineName, engine) in engines() {
                let answers = PasswordAnswers.always(correctPassword)
                let url = fixture("zip_aes256.zip")
                let destination = try tempDirectory()
                defer { try? FileManager.default.removeItem(at: destination) }

                let load = try await engine.loadArchive(url: url, passwordResolver: answers.resolver)
                let files = load.items.values.filter { $0.type == .file }
                #expect(
                    files.count == payloadFiles.count,
                    "\(engineName): expected \(payloadFiles.count) files, got \(files.count)"
                )

                let result = try await engine.extract(
                    items: Array(files),
                    from: url,
                    to: destination,
                    passwordResolver: answers.resolver
                )

                for file in files {
                    let extracted = try #require(result[file], "\(engineName): no url for \(file.name)")
                    let path = try #require(file.virtualPath)
                    #expect(matchesPayload(extracted, path), "\(engineName): \(path) wrong")
                }
            }
        }
    }

    // MARK: - Wrong password

    @MainActor struct WrongPasswordTests {

        /// A wrong password must surface as an error. Silently writing a 0-byte
        /// file and reporting success is the worst possible outcome — the user
        /// has no idea anything went wrong.
        @Test(arguments: ["zip_zipcrypto.zip", "zip_aes256.zip", "7z_aes256.7z"])
        func wrongPasswordThrowsInsteadOfWritingEmptyFile(name: String) async throws {
            for (engineName, engine) in engines() {
                // XAD cannot open a header-encrypted archive: the header has to be
                // decrypted during init and XADArchive only accepts a password
                // afterwards. Covered by xadCannotOpenHeaderEncryptedArchives.
                if engineName == "xad" && name.contains("encrypted_header") { continue }

                // One wrong answer, then cancel — bounded either way.
                let answers = PasswordAnswers("definitely-not-the-password")
                let url = fixture(name)
                let destination = try tempDirectory()
                defer { try? FileManager.default.removeItem(at: destination) }

                let load = try await engine.loadArchive(url: url, passwordResolver: answers.resolver)
                let hello = try #require(load.items.values.first { $0.virtualPath == helloPath })

                await #expect(throws: (any Error).self, "\(engineName)/\(name): wrong password reported success") {
                    _ = try await engine.extract(
                        items: [hello],
                        from: url,
                        to: destination,
                        passwordResolver: answers.resolver
                    )
                }

                // No half-written garbage left where the user asked for a file.
                let leftover = destination.appendingPathComponent(helloPath)
                #expect(
                    FileManager.default.fileExists(atPath: leftover.path) == false,
                    "\(engineName)/\(name): empty file left behind after failure"
                )
            }
        }

        /// A wrong password has to come back to the user, and the request must
        /// say which attempt this is so the UI can show "wrong password".
        @Test(arguments: ["zip_zipcrypto.zip", "zip_aes256.zip", "7z_aes256.7z"])
        func wrongPasswordIsRepromptedThenSucceeds(name: String) async throws {
            for (engineName, engine) in engines() {
                // XAD cannot open a header-encrypted archive: the header has to be
                // decrypted during init and XADArchive only accepts a password
                // afterwards. Covered by xadCannotOpenHeaderEncryptedArchives.
                if engineName == "xad" && name.contains("encrypted_header") { continue }

                let answers = PasswordAnswers("wrong-first-try", correctPassword)
                let url = fixture(name)
                let destination = try tempDirectory()
                defer { try? FileManager.default.removeItem(at: destination) }

                let load = try await engine.loadArchive(url: url, passwordResolver: answers.resolver)
                let hello = try #require(load.items.values.first { $0.virtualPath == helloPath })

                let result = try await engine.extract(
                    items: [hello],
                    from: url,
                    to: destination,
                    passwordResolver: answers.resolver
                )

                let extracted = try #require(result[hello])
                #expect(
                    contents(of: extracted) == helloContents,
                    "\(engineName)/\(name): retry with the right password did not recover"
                )
                let attempts = await answers.attempts
                #expect(
                    attempts.suffix(2) == [1, 2],
                    "\(engineName)/\(name): attempt counter did not advance, got \(attempts)"
                )
            }
        }

        /// The listing of a header-encrypted 7z cannot be read at all without
        /// the password, so the retry has to happen during load.
        @Test func wrongPasswordOnHeaderEncrypted7zIsReprompted() async throws {
            let answers = PasswordAnswers("wrong-first-try", correctPassword)
            let load = try await Archive7ZipEngine().loadArchive(
                url: fixture("7z_encrypted_header.7z"),
                passwordResolver: answers.resolver
            )

            #expect(load.items.values.contains { $0.virtualPath == helloPath })
            let attempts = await answers.attempts
            #expect(attempts == [1, 2], "got \(attempts)")
        }
    }

    // MARK: - A resolver that never gets it right

    /// The hang guard. Both engines used to retry a wrong password forever, at
    /// full CPU, with no prompt and no error — the XAD password tests were
    /// deleted from CoverageGapTests because of it. A resolver that keeps
    /// answering (as the ArchiveState cache effectively did) must not be able to
    /// spin them.
    ///
    /// The time limit only reports a hang; the real guard is the engines'
    /// attempt ceiling, which is why these finish in milliseconds.
    @MainActor struct AlwaysWrongPasswordTests {

        @Test(.timeLimit(.minutes(1)), arguments: ["zip_zipcrypto.zip", "zip_aes256.zip", "7z_aes256.7z"])
        func alwaysWrongPasswordTerminatesWithAnError(name: String) async throws {
            for (engineName, engine) in engines() {
                // XAD cannot open a header-encrypted archive: the header has to be
                // decrypted during init and XADArchive only accepts a password
                // afterwards. Covered by xadCannotOpenHeaderEncryptedArchives.
                if engineName == "xad" && name.contains("encrypted_header") { continue }

                // Unbounded: answers "wrong" every single time, forever.
                let answers = PasswordAnswers.always("definitely-not-the-password")
                let url = fixture(name)
                let destination = try tempDirectory()
                defer { try? FileManager.default.removeItem(at: destination) }

                let load = try await engine.loadArchive(url: url, passwordResolver: answers.resolver)
                let hello = try #require(load.items.values.first { $0.virtualPath == helloPath })

                await #expect(throws: (any Error).self, "\(engineName)/\(name)") {
                    _ = try await engine.extract(
                        items: [hello],
                        from: url,
                        to: destination,
                        passwordResolver: answers.resolver
                    )
                }

                let prompted = await answers.callCount
                #expect(prompted <= 21, "\(engineName)/\(name): asked \(prompted) times before giving up")
            }
        }

        /// Same guard one level up: a stale cached password must not spin the
        /// engine either, and the user has to see the prompt again.
        @Test(.timeLimit(.minutes(1)))
        func alwaysWrongPasswordThroughArchiveStateTerminates() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let prompts = Counter()
            state.passwordProvider = { _ in
                _ = await prompts.increment()
                return "definitely-not-the-password"
            }

            state.open(url: fixture("zip_aes256.zip"))
            try await state.openTask?.value

            let hello = try #require(state.entries.values.first { $0.virtualPath == helloPath })
            await #expect(throws: (any Error).self) {
                _ = try await state.extractToTemp(item: hello)
            }

            let count = await prompts.value
            #expect(count > 1, "the cached wrong password was never re-asked")
            #expect(count <= 21, "asked \(count) times before giving up")
        }
    }

    // MARK: - Cancelling the prompt

    @MainActor struct PasswordCancellationTests {

        @Test(arguments: ["zip_zipcrypto.zip", "zip_aes256.zip", "7z_aes256.7z"])
        func cancellingThePromptThrows(name: String) async throws {
            for (engineName, engine) in engines() {
                // XAD cannot open a header-encrypted archive: the header has to be
                // decrypted during init and XADArchive only accepts a password
                // afterwards. Covered by xadCannotOpenHeaderEncryptedArchives.
                if engineName == "xad" && name.contains("encrypted_header") { continue }

                let url = fixture(name)
                let destination = try tempDirectory()
                defer { try? FileManager.default.removeItem(at: destination) }

                let load = try await engine.loadArchive(url: url, passwordResolver: neverResolves)
                let hello = try #require(load.items.values.first { $0.virtualPath == helloPath })

                do {
                    _ = try await engine.extract(
                        items: [hello],
                        from: url,
                        to: destination,
                        passwordResolver: neverResolves
                    )
                    Issue.record("\(engineName)/\(name): cancelling the prompt still reported success")
                } catch ArchiveError.passwordCancelled {
                    // expected
                } catch {
                    Issue.record("\(engineName)/\(name): expected passwordCancelled, got \(error)")
                }
            }
        }

        @Test func cancellingHeaderEncrypted7zLoadThrows() async throws {
            await #expect(throws: (any Error).self) {
                _ = try await Archive7ZipEngine().loadArchive(
                    url: fixture("7z_encrypted_header.7z"),
                    passwordResolver: neverResolves
                )
            }
        }
    }

    // MARK: - Listing

    @MainActor struct PasswordListingTests {

        /// zip and plain-header 7z keep their file names in the clear, so
        /// listing them must not prompt for anything.
        @Test(arguments: [
            "zip_zipcrypto.zip", "zip_aes256.zip", "zip_aes128.zip", "7z_aes256.7z"
        ])
        func listsEncryptedArchiveWithoutPassword(name: String) async throws {
            for (engineName, engine) in engines() {
                // XAD cannot open a header-encrypted archive: the header has to be
                // decrypted during init and XADArchive only accepts a password
                // afterwards. Covered by xadCannotOpenHeaderEncryptedArchives.
                if engineName == "xad" && name.contains("encrypted_header") { continue }

                let answers = PasswordAnswers()
                let load = try await engine.loadArchive(
                    url: fixture(name),
                    passwordResolver: answers.resolver
                )

                #expect(
                    load.items.values.contains { $0.virtualPath == helloPath },
                    "\(engineName)/\(name): hello.txt not listed"
                )
                let prompted = await answers.callCount
                #expect(prompted == 0, "\(engineName)/\(name): listing asked for a password")
            }
        }

        /// XAD's one real limitation with encrypted archives: a header-encrypted
        /// archive has to be decrypted during `XADArchive` init, and XADArchive
        /// only accepts a password afterwards (its own hook is the synchronous
        /// `archiveNeedsPassword:` delegate, which can't drive an async resolver).
        /// XAD reports it as a plain decrunch error — the same code a damaged
        /// archive gets — so the message can only name the likely cause and point
        /// at 7-Zip. Either way it beats the old "Failed to create archive".
        @Test func xadCannotOpenHeaderEncryptedArchives() async throws {
            do {
                _ = try await ArchiveXadEngine().loadArchive(
                    url: fixture("7z_encrypted_header.7z"),
                    passwordResolver: PasswordAnswers.always(correctPassword).resolver
                )
                Issue.record("XAD opened a header-encrypted archive — limitation lifted, drop the skips")
            } catch ArchiveError.invalidArchive(let message) {
                #expect(message.localizedCaseInsensitiveContains("encrypted header"), "got \(message)")
                #expect(message.localizedCaseInsensitiveContains("7-zip"), "got \(message)")
            }
        }

        /// Everything *except* a header-encrypted archive must list through XAD
        /// without a password — including 7z, which XAD does support.
        @Test(arguments: ["zip_zipcrypto.zip", "zip_aes256.zip", "7z_aes256.7z"])
        func xadListsEncryptedArchivesWithoutPassword(name: String) async throws {
            let answers = PasswordAnswers()
            let load = try await ArchiveXadEngine().loadArchive(
                url: fixture(name),
                passwordResolver: answers.resolver
            )
            #expect(load.items.values.contains { $0.virtualPath == helloPath }, "\(name)")
            let prompted = await answers.callCount
            #expect(prompted == 0, "\(name): listing asked for a password")
        }

        /// `-mhe=on` encrypts the header, so the entry list itself is behind
        /// the password.
        @Test func headerEncrypted7zListsOnlyWithPassword() async throws {
            let answers = PasswordAnswers.always(correctPassword)
            let load = try await Archive7ZipEngine().loadArchive(
                url: fixture("7z_encrypted_header.7z"),
                passwordResolver: answers.resolver
            )

            #expect(load.items.values.contains { $0.virtualPath == helloPath })
            #expect(load.items.values.contains { $0.virtualPath == plainPath })
            let prompted = await answers.callCount
            #expect(prompted >= 1, "header-encrypted listing did not ask for a password")
        }

        /// The status bar has a lock indicator driven by `isEncrypted`.
        @Test(arguments: [
            ("zip_zipcrypto.zip", true),
            ("zip_aes256.zip", true),
            ("zip_mixed.zip", true),
            ("zip_nested_outer.zip", false)
        ])
        func reportsWhetherArchiveIsEncrypted(name: String, expected: Bool) async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.passwordProvider = { _ in correctPassword }
            state.open(url: fixture(name))
            try await state.openTask?.value

            #expect(state.isEncrypted == expected, "\(name)")
        }
    }

    // MARK: - Partially encrypted archives

    @MainActor struct MixedEncryptionTests {

        /// Everything under `folder/` is stored unencrypted next to the encrypted
        /// Extracting it must not prompt at all.
        @Test func plainEntryNeedsNoPassword() async throws {
            for (engineName, engine) in engines() {
                let answers = PasswordAnswers()
                let url = fixture("zip_mixed.zip")
                let destination = try tempDirectory()
                defer { try? FileManager.default.removeItem(at: destination) }

                let load = try await engine.loadArchive(url: url, passwordResolver: answers.resolver)
                let plain = try #require(load.items.values.first { $0.virtualPath == plainPath })

                let result = try await engine.extract(
                    items: [plain],
                    from: url,
                    to: destination,
                    passwordResolver: answers.resolver
                )

                let extracted = try #require(result[plain])
                #expect(matchesPayload(extracted, plainPath), "\(engineName): \(plainPath) wrong")
                let prompted = await answers.callCount
                #expect(prompted == 0, "\(engineName): plain entry asked for a password")
            }
        }

        /// Selecting the plain *and* the encrypted entry together still needs
        /// exactly one password.
        @Test func mixedSelectionPromptsOnceAndExtractsBoth() async throws {
            let engine = Archive7ZipEngine()
            let answers = PasswordAnswers.always(correctPassword)
            let url = fixture("zip_mixed.zip")
            let destination = try tempDirectory()
            defer { try? FileManager.default.removeItem(at: destination) }

            let load = try await engine.loadArchive(url: url, passwordResolver: answers.resolver)
            let plain = try #require(load.items.values.first { $0.virtualPath == plainPath })
            let secret = try #require(load.items.values.first { $0.virtualPath == helloPath })

            let result = try await engine.extract(
                items: [plain, secret],
                from: url,
                to: destination,
                passwordResolver: answers.resolver
            )

            #expect(matchesPayload(try #require(result[plain]), plainPath))
            #expect(contents(of: try #require(result[secret])) == helloContents)
            let prompted = await answers.callCount
            #expect(prompted == 1, "prompted \(prompted) times")
        }
    }

    // MARK: - RAR

    /// Encrypted RAR. RAR5 derives its key with PBKDF2-HMAC-SHA256 and RAR3/4
    /// with SHA-1, both through the 7-Zip crypto that was silently broken until
    /// v0.18.2, so these are the cases most likely to regress if the Opt sources
    /// ever get dropped again.
    ///
    /// The fixtures can only be *created* where `rar` runs (Windows/Linux) —
    /// `make_rar_fixtures.sh`, and `-ma4` for the RAR3/4 pair needs WinRAR 6.
    /// The suite stays gated on them existing so a fresh submodule checkout that
    /// lacks them skips rather than fails.
    @MainActor
    @Suite(.enabled(if: rarFixturesAvailable, "RAR fixtures missing — see make_rar_fixtures.sh"))
    struct EncryptedRarTests {

        @Test(arguments: [
            "rar5_aes.rar", "rar5_encrypted_header.rar",
            "rar4_aes.rar", "rar4_encrypted_header.rar"
        ])
        func extractsEncryptedRarEntryWithCorrectPassword(name: String) async throws {
            for (engineName, engine) in engines() {
                // XAD cannot open a header-encrypted archive: the header has to be
                // decrypted during init and XADArchive only accepts a password
                // afterwards. Covered by xadCannotOpenHeaderEncryptedArchives.
                if engineName == "xad" && name.contains("encrypted_header") { continue }

                let answers = PasswordAnswers.always(correctPassword)
                let url = fixture(name)
                let destination = try tempDirectory()
                defer { try? FileManager.default.removeItem(at: destination) }

                let load = try await engine.loadArchive(url: url, passwordResolver: answers.resolver)
                let hello = try #require(
                    load.items.values.first { $0.virtualPath == helloPath },
                    "\(engineName)/\(name): \(helloPath) missing from listing"
                )

                let result = try await engine.extract(
                    items: [hello],
                    from: url,
                    to: destination,
                    passwordResolver: answers.resolver
                )

                let extracted = try #require(result[hello], "\(engineName)/\(name): no url returned")
                #expect(
                    contents(of: extracted) == helloContents,
                    "\(engineName)/\(name): extracted contents wrong or file empty"
                )
            }
        }

        @Test(arguments: ["rar5_aes.rar", "rar4_aes.rar"])
        func wrongPasswordOnRarIsRepromptedThenSucceeds(name: String) async throws {
            for (engineName, engine) in engines() {
                // XAD cannot open a header-encrypted archive: the header has to be
                // decrypted during init and XADArchive only accepts a password
                // afterwards. Covered by xadCannotOpenHeaderEncryptedArchives.
                if engineName == "xad" && name.contains("encrypted_header") { continue }

                let answers = PasswordAnswers("wrong-first-try", correctPassword)
                let url = fixture(name)
                let destination = try tempDirectory()
                defer { try? FileManager.default.removeItem(at: destination) }

                let load = try await engine.loadArchive(url: url, passwordResolver: answers.resolver)
                let hello = try #require(load.items.values.first { $0.virtualPath == helloPath })

                let result = try await engine.extract(
                    items: [hello],
                    from: url,
                    to: destination,
                    passwordResolver: answers.resolver
                )

                #expect(
                    contents(of: try #require(result[hello])) == helloContents,
                    "\(engineName)/\(name): retry with the right password did not recover"
                )
            }
        }

        /// `rar -hp` encrypts the header, so the listing itself needs the
        /// password — the RAR equivalent of 7z `-mhe=on`.
        @Test(arguments: ["rar5_encrypted_header.rar", "rar4_encrypted_header.rar"])
        func headerEncryptedRarListsOnlyWithPassword(name: String) async throws {
            let answers = PasswordAnswers.always(correctPassword)
            let load = try await Archive7ZipEngine().loadArchive(
                url: fixture(name),
                passwordResolver: answers.resolver
            )
            #expect(load.items.values.contains { $0.virtualPath == helloPath }, "\(name)")

            let prompted = await answers.callCount
            #expect(prompted >= 1, "\(name): header-encrypted listing did not ask for a password")

            await #expect(throws: (any Error).self, "\(name): listed without a password") {
                _ = try await Archive7ZipEngine().loadArchive(
                    url: fixture(name),
                    passwordResolver: neverResolves
                )
            }
        }
    }

    // MARK: - The path the app actually takes

    /// Everything else here pins an engine with a test-only selector. The app
    /// does not: it runs `ArchiveState.open(url:)` against the production
    /// `ArchiveEngineSelector`, which resolves the engine from the catalog and
    /// the user's settings, after `ArchiveTypeDetector` has identified the file.
    ///
    /// That whole strip — detection, engine resolution, the loader — had no
    /// coverage, which is how "rar4_encrypted_header.rar: Unsupported or invalid
    /// archive" could be reported while every engine-level test passed.
    @MainActor struct ProductionOpenPathTests {

        /// Never reads UserDefaults: the engine is a parameter, so the test says
        /// which engine it is exercising instead of inheriting whatever the
        /// machine happens to have configured.
        private func state(engine: ArchiveEngineType) -> ArchiveState {
            ArchiveState(
                catalog: ArchiveTypeCatalog(),
                engineSelector: ArchiveEngineSelectorPinned(engine)
            )
        }

        /// Every encrypted fixture must open through the real selector — no
        /// "unsupported or invalid archive", and the entries must actually land.
        @Test(arguments: [
            "zip_zipcrypto.zip", "zip_aes256.zip", "zip_aes128.zip", "zip_mixed.zip",
            "zip_unicode_pw.zip", "zip_symbol_pw.zip", "zip_long_pw.zip",
            "zip_nested_outer.zip",
            "7z_aes256.7z", "7z_encrypted_header.7z", "7z_symbol_pw.7z"
        ])
        func opensThroughTheProductionSelector(name: String) async throws {
            let password: String
            switch name {
            case "zip_unicode_pw.zip": password = unicodePassword
            case "zip_symbol_pw.zip", "7z_symbol_pw.7z": password = symbolPassword
            case "zip_long_pw.zip": password = longPassword
            default: password = correctPassword
            }

            // Both engines the catalog offers for these formats. SWC is listed
            // for zip too but only implements LZ4, so it is not an archive
            // reader — see swcCannotReadEncryptedZip.
            for engine in [ArchiveEngineType.`7zip`, .xad] {
                let state = state(engine: engine)
                state.passwordProvider = { _ in password }
                state.open(url: fixture(name))
                try await state.openTask?.value

                #expect(state.error == nil, "\(engine.configId)/\(name): \(state.error ?? "")")
                #expect(state.hasArchive, "\(engine.configId)/\(name): archive did not open")
                #expect(!state.entries.isEmpty, "\(engine.configId)/\(name): no entries")
            }
        }

        /// Same, for RAR — the format the failure was reported against. RAR has
        /// no fallback engine in the catalog, so whichever engine the selector
        /// picks has to cope with an encrypted header on its own.
        @Test(.enabled(if: rarFixturesAvailable, "RAR fixtures missing"), arguments: [
            "rar5_aes.rar", "rar5_encrypted_header.rar",
            "rar4_aes.rar", "rar4_encrypted_header.rar"
        ])
        func opensRarThroughTheProductionSelector(name: String) async throws {
            for engine in [ArchiveEngineType.`7zip`, .xad] {
                let state = state(engine: engine)
                state.passwordProvider = { _ in correctPassword }
                state.open(url: fixture(name))
                try await state.openTask?.value

                #expect(state.error == nil, "\(engine.configId)/\(name): \(state.error ?? "")")
                #expect(state.hasArchive, "\(engine.configId)/\(name): archive did not open")
                #expect(
                    state.entries.values.contains { $0.virtualPath == helloPath },
                    "\(engine.configId)/\(name): \(helloPath) missing after open"
                )
            }
        }

        /// Reported from the app: dropping `rar5_encrypted_header.rar` in gave
        /// "Unsupported or invalid archive". The logs showed why —
        /// `Engine selected engine: xad` — because the user had XAD chosen for
        /// RAR, and XAD cannot open a header-encrypted archive at all.
        ///
        /// The tests above missed it because a fresh test process has no
        /// `archiveEngineConfigs` override, so the selector fell back to the
        /// catalog default (7-Zip), which handles these fine. The override is
        /// what makes it fail.
        ///
        /// 7-Zip is listed for both formats and can read them, so the app should
        /// use it rather than dead-ending on a settings hint.
        @Test(.enabled(if: rarFixturesAvailable, "RAR fixtures missing"), arguments: [
            ("rar5_encrypted_header.rar", "rar"),
            ("rar4_encrypted_header.rar", "rar"),
            ("7z_encrypted_header.7z", "7zip")
        ])
        func opensHeaderEncryptedArchiveWhenXadIsSelected(name: String, formatId: String) async throws {
            let state = state(engine: .xad)
            state.passwordProvider = { _ in correctPassword }
            state.open(url: fixture(name))
            try await state.openTask?.value

            #expect(state.error == nil, "\(name): \(state.error ?? "")")
            #expect(state.hasArchive, "\(name): archive did not open")
            #expect(
                state.entries.values.contains { $0.virtualPath == helloPath },
                "\(name): \(helloPath) missing after open"
            )
        }

        /// …and the archive has to stay usable afterwards. Falling back only for
        /// the listing would open the window and then fail on the first
        /// extraction, which is worse than refusing outright.
        @Test(.enabled(if: rarFixturesAvailable, "RAR fixtures missing"))
        func extractsFromHeaderEncryptedArchiveWhenXadIsSelected() async throws {
            let state = state(engine: .xad)
            state.passwordProvider = { _ in correctPassword }
            state.open(url: fixture("rar5_encrypted_header.rar"))
            try await state.openTask?.value

            let hello = try #require(state.entries.values.first { $0.virtualPath == helloPath })
            let extracted = try await state.extractToTemp(item: hello)
            #expect(matchesPayload(extracted, helloPath), "extracted contents wrong or empty")
        }

        /// A file the detector cannot place must say so, not fall through with a
        /// blank reason — the log line that started this was useless precisely
        /// because the message was thrown away.
        @Test func unrecognisedFileReportsWhy() async throws {
            let dir = try tempDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let bogus = dir.appendingPathComponent("not-an-archive.bin")
            try Data(repeating: 0x5A, count: 4096).write(to: bogus)

            let state = state(engine: .`7zip`)
            state.open(url: bogus)
            try await state.openTask?.value

            let message = try #require(state.error, "no reason reported")
            #expect(message.localizedCaseInsensitiveContains("not-an-archive.bin"), "got \(message)")
        }
    }

    // MARK: - Progress and cancellation on encrypted archives

    @MainActor struct EncryptedProgressTests {

        /// Decryption sits between the archive and the progress counters, so
        /// confirm the byte progress still arrives and still only moves forward.
        @Test(arguments: ["zip_aes256.zip", "zip_zipcrypto.zip", "7z_aes256.7z"])
        func reportsByteProgressWhileDecrypting(name: String) async throws {
            let engine = Archive7ZipEngine()
            let answers = PasswordAnswers.always(correctPassword)
            let url = fixture(name)
            let destination = try tempDirectory()
            defer { try? FileManager.default.removeItem(at: destination) }

            let load = try await engine.loadArchive(url: url, passwordResolver: answers.resolver)
            let files = load.items.values.filter { $0.type == .file }

            let seen = ProgressLog()
            _ = try await engine.extract(
                items: Array(files),
                from: url,
                to: destination,
                passwordResolver: answers.resolver,
                onProgress: { completed, total in
                    seen.add(completed, total)
                    return true
                }
            )

            let completed = seen.completedValues
            #expect(!completed.isEmpty, "\(name): no progress reported")
            #expect(completed == completed.sorted(), "\(name): progress went backwards")
        }

        /// Cancelling from the progress callback has to abort the extraction, not
        /// get swallowed by the password retry loop.
        @Test func cancellingFromProgressAbortsEncryptedExtraction() async throws {
            let engine = Archive7ZipEngine()
            let answers = PasswordAnswers.always(correctPassword)
            let url = fixture("zip_aes256.zip")
            let destination = try tempDirectory()
            defer { try? FileManager.default.removeItem(at: destination) }

            let load = try await engine.loadArchive(url: url, passwordResolver: answers.resolver)
            let files = load.items.values.filter { $0.type == .file }

            await #expect(throws: CancellationError.self) {
                _ = try await engine.extract(
                    items: Array(files),
                    from: url,
                    to: destination,
                    passwordResolver: answers.resolver,
                    onProgress: { _, _ in false }
                )
            }
        }
    }

    // MARK: - Editing an encrypted archive

    @MainActor struct EncryptedEditTests {

        /// Deleting an entry rewrites the archive by copying the other entries
        /// through. Those entries are encrypted, so the rewrite must keep them
        /// readable with the original password rather than corrupting or
        /// silently decrypting them.
        @Test func deletingAnEntryKeepsTheRestEncrypted() async throws {
            let work = try tempDirectory()
            defer { try? FileManager.default.removeItem(at: work) }
            let archive = work.appendingPathComponent("edit_aes256.zip")
            try FileManager.default.copyItem(at: fixture("zip_aes256.zip"), to: archive)

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.passwordProvider = { _ in correctPassword }
            state.open(url: archive)
            try await state.openTask?.value

            let readme = try #require(state.entries.values.first { $0.virtualPath == plainPath })
            state.remove(items: [readme])
            await state.save()?.value
            #expect(state.error == nil, "save reported \(state.error ?? "")")

            // Reopen from scratch: the deleted entry must be gone and the ones
            // copied through must still decrypt to their original bytes.
            let reopened = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            reopened.passwordProvider = { _ in correctPassword }
            reopened.open(url: archive)
            try await reopened.openTask?.value

            #expect(reopened.entries.values.contains { $0.virtualPath == plainPath } == false)
            for path in payloadFiles where path != plainPath {
                let item = try #require(
                    reopened.entries.values.first { $0.virtualPath == path },
                    "\(path) vanished from the rewritten archive"
                )
                let extracted = try await reopened.extractToTemp(item: item)
                #expect(matchesPayload(extracted, path), "\(path) did not survive the rewrite")
            }
            #expect(reopened.isEncrypted == true, "the rewrite dropped the encryption")
        }
    }

    // MARK: - ArchiveState: caching and re-prompting

    @MainActor struct ArchiveStatePasswordFlowTests {

        /// The password is cached per archive, so a second extraction is silent.
        @Test func correctPasswordIsCachedAcrossExtractions() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let prompts = Counter()
            state.passwordProvider = { _ in
                _ = await prompts.increment()
                return correctPassword
            }

            state.open(url: fixture("zip_aes256.zip"))
            try await state.openTask?.value

            let hello = try #require(state.entries.values.first { $0.virtualPath == helloPath })
            #expect(contents(of: try await state.extractToTemp(item: hello)) == helloContents)
            #expect(contents(of: try await state.extractToTemp(item: hello)) == helloContents)

            let count = await prompts.value
            #expect(count == 1, "prompted \(count) times, expected 1")
        }

        /// The bug behind "0% and 100% CPU": the cached password was handed back
        /// on every retry, so a wrong one made the engine loop forever without
        /// ever asking the user again.
        @Test func wrongCachedPasswordIsDiscardedAndReprompted() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let prompts = Counter()
            state.passwordProvider = { _ in
                let attempt = await prompts.increment()
                // Cancel after a few tries so a broken loop fails instead of
                // hanging the suite.
                if attempt > 3 { return nil }
                return attempt == 1 ? "wrong-first-try" : correctPassword
            }

            state.open(url: fixture("zip_aes256.zip"))
            try await state.openTask?.value

            let hello = try #require(state.entries.values.first { $0.virtualPath == helloPath })
            let extracted = try await state.extractToTemp(item: hello)

            #expect(contents(of: extracted) == helloContents)
            let count = await prompts.value
            #expect(count == 2, "prompted \(count) times, expected 2")
        }

        /// Cancelling surfaces an error rather than an empty extraction.
        @Test func cancellingThePromptSetsAnError() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.passwordProvider = { _ in nil }

            state.open(url: fixture("zip_aes256.zip"))
            try await state.openTask?.value

            let hello = try #require(state.entries.values.first { $0.virtualPath == helloPath })
            await #expect(throws: (any Error).self) {
                _ = try await state.extractToTemp(item: hello)
            }
        }

        /// Dismissing the prompt is the user backing out, so the progress window
        /// must report cancelled — not a red failure with a generic message.
        @Test func cancellingThePromptReportsCancelledNotFailed() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let center = ExtractionProgressCenter()
            state.progressCenter = center
            state.passwordProvider = { _ in nil }

            state.open(url: fixture("zip_aes256.zip"))
            try await state.openTask?.value

            let hello = try #require(state.entries.values.first { $0.virtualPath == helloPath })
            state.extract(items: [hello], to: try tempDirectory())

            try await Task.sleep(for: .milliseconds(400))
            let job = try #require(center.jobs.first)
            #expect(job.state == .cancelled, "got \(job.state)")
        }

        /// Finder's "Extract Here" and QuickLook build an ArchiveState with no
        /// passwordProvider — there is nowhere to show a prompt. That has to fail
        /// with a message saying what to do, not vanish silently.
        @Test func extractionWithNoPromptAvailableExplainsItself() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let center = ExtractionProgressCenter()
            state.progressCenter = center
            // deliberately no passwordProvider

            state.open(url: fixture("zip_aes256.zip"))
            try await state.openTask?.value

            let hello = try #require(state.entries.values.first { $0.virtualPath == helloPath })
            state.extract(items: [hello], to: try tempDirectory())

            try await Task.sleep(for: .milliseconds(400))
            let job = try #require(center.jobs.first)
            guard case .failed(let message) = job.state else {
                Issue.record("expected a failed job, got \(job.state)")
                return
            }
            #expect(message.localizedCaseInsensitiveContains("password protected"), "got \(message)")
        }

        /// A wrong password that the user gives up on has to reach the progress
        /// window as a readable message, not "The operation couldn't be
        /// completed" — the customer's "there is no message".
        @Test func exhaustedPasswordAttemptsReportAReadableMessage() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let center = ExtractionProgressCenter()
            state.progressCenter = center
            state.passwordProvider = { _ in "definitely-not-the-password" }

            state.open(url: fixture("zip_aes256.zip"))
            try await state.openTask?.value

            let hello = try #require(state.entries.values.first { $0.virtualPath == helloPath })
            state.extract(items: [hello], to: try tempDirectory())

            try await Task.sleep(for: .milliseconds(600))
            let job = try #require(center.jobs.first)
            guard case .failed(let message) = job.state else {
                Issue.record("expected a failed job, got \(job.state)")
                return
            }
            #expect(message.localizedCaseInsensitiveContains("password"), "got \(message)")
            #expect(state.error?.localizedCaseInsensitiveContains("password") == true, "got \(state.error ?? "nil")")
        }

        /// Opening a text file straight out of an encrypted archive — the
        /// customer's "text files are correctly opened directly from the
        /// archive" case.
        @Test(arguments: ["zip_zipcrypto.zip", "zip_aes256.zip", "7z_aes256.7z"])
        func opensFileDirectlyFromEncryptedArchive(name: String) async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let opened = URLRecorder()
            state.openFileExternally = { url in
                MainActor.assumeIsolated { opened.record(url) }
            }
            state.passwordProvider = { _ in correctPassword }

            state.open(url: fixture(name))
            try await state.openTask?.value

            let hello = try #require(state.entries.values.first { $0.virtualPath == helloPath })
            try await state.openFile(hello)

            let handed = try #require(opened.urls.first, "\(name): nothing handed to the system")
            #expect(contents(of: handed) == helloContents, "\(name): opened an empty/wrong file")
        }

        /// An encrypted archive nested inside a plain one: the outer archive is
        /// extracted first, so the prompt has to reach one level down.
        @Test func opensEncryptedArchiveNestedInPlainArchive() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.passwordProvider = { _ in correctPassword }

            state.open(url: fixture("zip_nested_outer.zip"))
            try await state.openTask?.value

            let inner = try #require(state.entries.values.first { $0.name == "inner_encrypted.zip" })
            try await state.openAsync(item: inner)

            let hello = try #require(
                state.entries.values.first { $0.virtualPath == helloPath },
                "inner archive did not list"
            )
            #expect(contents(of: try await state.extractToTemp(item: hello)) == helloContents)
        }
    }
}

/// Counts prompt callbacks. An actor because `passwordProvider` is called
/// from the engines' non-main executors.
private actor Counter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

/// Records the byte-progress callbacks an extraction makes. Called on the
/// extraction thread, hence the lock.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var completed: [Int64] = []

    func add(_ completed: Int64, _ total: Int64) {
        lock.lock()
        self.completed.append(completed)
        lock.unlock()
    }

    var completedValues: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }
}

/// Collects the URLs `ArchiveState.openFileExternally` hands to the system.
@MainActor
private final class URLRecorder {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}
