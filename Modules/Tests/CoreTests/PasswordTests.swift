//
//  PasswordTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 29.07.26.
//

import Testing
import Foundation
import Swift7zip
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

/// One of the `defaultArchive.*` fixtures, which all pack the same payload.
/// The engine-fallback tests need a format only one engine reads.
private func defaultArchive(_ ext: String) -> URL {
    let folder = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
    return folder.appendingPathComponent("defaultArchive.\(ext)")
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
                // Three answers for two openings and one correction: listing the
                // archive opens it and takes the first, extracting opens it again
                // and takes the second, and only then does the wrong password
                // show — nothing in a zip or a 7z lets one be checked earlier.
                // That third request is the one that has to arrive as attempt 2.
                let answers = PasswordAnswers("wrong-first-try", "wrong-again", correctPassword)
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
                // Never answers, which is what Quick Look and Finder's "Extract
                // Here" do — they carry no prompt at all. An archive whose names
                // read without a password still has to list them.
                let answers = PasswordAnswers()
                let load = try await engine.loadArchive(
                    url: fixture(name),
                    passwordResolver: answers.resolver
                )

                #expect(
                    load.items.values.contains { $0.virtualPath == helloPath },
                    "\(engineName)/\(name): hello.txt not listed"
                )
                #expect(load.isEncrypted, "\(engineName)/\(name): not reported as encrypted")
            }
        }

        /// A header-encrypted archive has to be decrypted during `XADArchive`
        /// init, which used to put it out of XAD's reach: MacPacker handed over a
        /// password only after something failed, and by then the archive had not
        /// opened. Now the password is resolved as part of opening, through the
        /// delegate XADArchive takes at init, and these read like any other.
        @Test func xadOpensHeaderEncryptedArchives() async throws {
            let load = try await ArchiveXadEngine().loadArchive(
                url: fixture("7z_encrypted_header.7z"),
                passwordResolver: PasswordAnswers.always(correctPassword).resolver
            )
            #expect(load.items.values.contains { $0.virtualPath == helloPath })
            #expect(load.isEncrypted)
        }

        /// And without a password it still cannot, with a message that says where
        /// to go — the message automatic mode's fallback is built on.
        @Test func xadSaysWhereToGoWhenAHeaderStaysEncrypted() async throws {
            do {
                _ = try await ArchiveXadEngine().loadArchive(
                    url: fixture("7z_encrypted_header.7z"),
                    passwordResolver: neverResolves
                )
                Issue.record("XAD opened a header-encrypted archive with no password")
            } catch ArchiveError.invalidArchive(let message) {
                #expect(message.localizedCaseInsensitiveContains("encrypted header"), "got \(message)")
                #expect(message.localizedCaseInsensitiveContains("7-zip"), "got \(message)")
            }
        }

        /// Everything *except* a header-encrypted archive must list through XAD
        /// even when no password is given — including 7z, which XAD does support.
        @Test(arguments: ["zip_zipcrypto.zip", "zip_aes256.zip", "7z_aes256.7z"])
        func xadListsEncryptedArchivesWithoutPassword(name: String) async throws {
            let load = try await ArchiveXadEngine().loadArchive(
                url: fixture(name),
                passwordResolver: neverResolves
            )
            #expect(load.items.values.contains { $0.virtualPath == helloPath }, "\(name)")
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
        /// entries, and has to come out whether or not a password is ever given.
        ///
        /// The archive does have encrypted entries, so opening it asks — that is
        /// what the prompt moving to the open means for a mixed archive. What
        /// must not happen is the plain entry becoming unreachable because the
        /// question went unanswered.
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
            }
        }

        /// Selecting the plain *and* the encrypted entry together still needs
        /// exactly one password — one the user types once.
        ///
        /// The resolver is consulted twice, because listing the archive and
        /// extracting from it each open it and each needs the password then. Both
        /// arrive as attempt 1, which is what says the password was accepted and
        /// nothing was re-asked as a correction; in the app the second one is
        /// served from the cache and the user sees a single prompt.
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
            let attempts = await answers.attempts
            #expect(attempts.allSatisfy { $0 == 1 }, "a password was re-asked: \(attempts)")
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

        /// Manual mode: the chosen engine is the only engine, exactly as when a
        /// user has picked one in Settings. These are the project's existing
        /// single-engine doubles, which inherit `allowsEngineFallback == false`,
        /// so nothing can silently answer for the engine under test.
        private func manualState(engine: ArchiveEngineType) -> ArchiveState {
            let selector: any ArchiveEngineSelectorProtocol = switch engine {
            case .`7zip`: ArchiveEngineSelector7zip()
            case .xad:    ArchiveEngineSelectorXad()
            case .swc:    ArchiveEngineSelectorSwc()
            }
            return ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: selector)
        }

        /// Automatic mode, with the catalog default for `formatId` moved to
        /// `engine`.
        ///
        /// This is the production selector and the production config store — the
        /// only injected things are the catalog default and an isolated defaults
        /// suite, so nothing here touches the real user's settings. Automatic
        /// mode always uses the catalog default, so moving that default is the
        /// only honest way to make MacPacker choose an engine that cannot read
        /// the archive.
        private func automaticState(
            defaultEngine engine: ArchiveEngineType,
            for formatId: String
        ) -> ArchiveState {
            let catalog = ArchiveTypeCatalogWithDefault([formatId: engine])
            let store = ArchiveEngineConfigStore(catalog: catalog, defaults: isolatedDefaults())
            store.isAutomatic = true
            return ArchiveState(
                catalog: ArchiveTypeCatalog(),
                engineSelector: ArchiveEngineSelector(catalog: ArchiveTypeCatalog(), configStore: store)
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
                // XAD cannot read a header-encrypted archive at all. Automatic
                // mode is what rescues those, covered by
                // fallsBackWhenTheSelectedEngineCannotRead. Asserting them here
                // would let the fallback masquerade as "XAD works".
                if engine == .xad && name.contains("encrypted_header") { continue }

                let state = manualState(engine: engine)
                state.passwordProvider = { _ in password }
                state.open(url: fixture(name))
                try await state.openTask?.value

                #expect(state.error == nil, "\(engine.configId)/\(name): \(state.error ?? "")")
                #expect(state.hasArchive, "\(engine.configId)/\(name): archive did not open")
                #expect(!state.entries.isEmpty, "\(engine.configId)/\(name): no entries")
                // The engine under test must be the one that served it — a
                // silent fallback has to fail this, not pass it.
                #expect(
                    state.activeEngine == engine,
                    "\(engine.configId)/\(name): served by \(state.activeEngine?.configId ?? "nothing") instead"
                )
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
                // XAD cannot read a header-encrypted archive at all. Automatic
                // mode is what rescues those, covered by
                // fallsBackWhenTheSelectedEngineCannotRead. Asserting them here
                // would let the fallback masquerade as "XAD works".
                if engine == .xad && name.contains("encrypted_header") { continue }

                let state = manualState(engine: engine)
                state.passwordProvider = { _ in correctPassword }
                state.open(url: fixture(name))
                try await state.openTask?.value

                #expect(state.error == nil, "\(engine.configId)/\(name): \(state.error ?? "")")
                #expect(state.hasArchive, "\(engine.configId)/\(name): archive did not open")
                #expect(
                    state.entries.values.contains { $0.virtualPath == helloPath },
                    "\(engine.configId)/\(name): \(helloPath) missing after open"
                )
                // The engine under test must be the one that served it — a
                // silent fallback has to fail this, not pass it.
                #expect(
                    state.activeEngine == engine,
                    "\(engine.configId)/\(name): served by \(state.activeEngine?.configId ?? "nothing") instead"
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
        ///
        /// The case used to be a header-encrypted RAR or 7z, which XAD could not
        /// open at all. It can now — the password reaches it when the archive is
        /// opened — so the engines part ways somewhere else: a disk image only
        /// 7-Zip reads.
        @Test(arguments: [
            ("squashfs", "squashfs"),
            ("qcow2", "qcow2"),
            ("fat", "fat")
        ])
        func fallsBackWhenTheChosenEngineCannotRead(name: String, formatId: String) async throws {
            let state = automaticState(defaultEngine: .xad, for: formatId)
            state.passwordProvider = { _ in correctPassword }
            state.open(url: defaultArchive(name))
            try await state.openTask?.value

            #expect(state.error == nil, "\(name): \(state.error ?? "")")
            #expect(state.hasArchive, "\(name): archive did not open")
            #expect(
                state.entries.values.contains { $0.virtualPath == helloPath },
                "\(name): \(helloPath) missing after open"
            )
            // It opened because MacPacker changed engine, not because XAD
            // suddenly grew the capability.
            #expect(state.activeEngine == .`7zip`, "\(name): expected the 7-Zip fallback")
        }

        /// …and the archive has to stay usable afterwards. Falling back only for
        /// the listing would open the window and then fail on the first
        /// extraction, which is worse than refusing outright.
        @Test(.enabled(if: rarFixturesAvailable, "RAR fixtures missing"))
        func extractsFromHeaderEncryptedArchiveWhenXadIsSelected() async throws {
            let state = automaticState(defaultEngine: .xad, for: "rar")
            state.passwordProvider = { _ in correctPassword }
            state.open(url: fixture("rar5_encrypted_header.rar"))
            try await state.openTask?.value

            let hello = try #require(state.entries.values.first { $0.virtualPath == helloPath })
            let extracted = try await state.extractToTemp(item: hello)
            #expect(matchesPayload(extracted, helloPath), "extracted contents wrong or empty")
        }

        /// The other half of the toggle. Same archive, same engine, but the user
        /// picked it — so MacPacker must report what XAD cannot do instead of
        /// quietly using a different engine. If this ever starts passing, the
        /// engine setting has stopped meaning anything.
        @Test(arguments: ["squashfs", "qcow2", "fat"])
        func doesNotFallBackWhenTheUserPickedTheEngine(name: String) async throws {
            let state = manualState(engine: .xad)
            state.passwordProvider = { _ in correctPassword }
            state.open(url: defaultArchive(name))
            try await state.openTask?.value

            #expect(state.hasArchive == false, "\(name): opened despite manual XAD")
            let message = try #require(state.error, "\(name): failed with no reason")
            #expect(
                message.localizedCaseInsensitiveContains("7-Zip"),
                "\(name): message does not point anywhere useful — \(message)"
            )
        }

        /// Cancelling the prompt on the *fallback* engine must stay a
        /// cancellation.
        ///
        /// The fallback loop swallowed every error from a candidate engine and
        /// then reported the original engine's reason, so dismissing the password
        /// prompt came back as "Could not open … with the XAD engine" — blaming
        /// an engine the user never saw, for a file that is perfectly readable.
        /// Task cancellation and real extraction errors were lost the same way.
        @Test(.enabled(if: rarFixturesAvailable, "RAR fixtures missing"))
        func cancellingThePromptOnTheFallbackEngineIsNotReportedAsInvalid() async throws {
            // XAD is the default and cannot open a header-encrypted archive, so
            // the loader falls back to 7-Zip, which needs the password to list.
            let state = automaticState(defaultEngine: .xad, for: "rar")
            state.passwordProvider = { _ in nil }

            state.open(url: fixture("rar5_encrypted_header.rar"))
            try await state.openTask?.value

            #expect(state.hasArchive == false)
            let message = try #require(state.error, "no reason reported")
            #expect(
                message.localizedCaseInsensitiveContains("cancel"),
                "cancelling was not reported as a cancellation — got \(message)"
            )
            #expect(
                message.localizedCaseInsensitiveContains("XAD") == false,
                "blamed the engine the user never chose — got \(message)"
            )
        }

        /// A failed open has to leave something the window can show.
        ///
        /// With XAD picked by hand and a header-encrypted archive, the log said
        /// exactly what went wrong and the UI said nothing: `open` ends in
        /// `reset()`, so the window falls back to its empty state and the user
        /// sees their drag do nothing at all. `error` was set, but the only thing
        /// reading it was the Finder compress flow.
        @Test func aFailedOpenLeavesSomethingToShowTheUser() async throws {
            let state = manualState(engine: .xad)
            state.passwordProvider = { _ in correctPassword }
            state.open(url: defaultArchive("squashfs"))
            try await state.openTask?.value

            #expect(state.hasArchive == false)
            let shown = try #require(state.openError, "nothing for the window to show")
            #expect(
                shown.localizedCaseInsensitiveContains("XAD"),
                "does not name the engine that failed — \(shown)"
            )
            #expect(
                shown.localizedCaseInsensitiveContains("7-Zip")
                    || shown.localizedCaseInsensitiveContains("automatic"),
                "does not tell the user what to do about it — \(shown)"
            )
        }

        /// And it must not linger: the next open starts clean.
        @Test func openErrorIsClearedByTheNextOpen() async throws {
            let state = manualState(engine: .xad)
            state.passwordProvider = { _ in correctPassword }

            state.open(url: defaultArchive("squashfs"))
            try await state.openTask?.value
            #expect(state.openError != nil, "expected the first open to fail")

            state.open(url: fixture("zip_zipcrypto.zip"))
            try await state.openTask?.value
            #expect(state.openError == nil, "a stale failure survived the next open")
        }

        /// Cancelling must not reach past the open that replaced it.
        ///
        /// cancelCurrentOperation() awaits the loader before clearing it and
        /// calling reset(). A new open started during that await owns the state
        /// and has its own loader by the time it resumes, so the stale cancel
        /// would wipe an archive the user had just successfully opened.
        @Test func cancelDoesNotWipeAnOpenThatReplacedIt() async throws {
            let state = manualState(engine: .`7zip`)
            state.passwordProvider = { _ in correctPassword }

            state.open(url: fixture("zip_aes256.zip"))
            state.cancelCurrentOperation()

            // Replaces both the cancelled open and its loader.
            state.open(url: fixture("zip_zipcrypto.zip"))
            try await state.openTask?.value

            // Give any in-flight cancel a chance to land late.
            try await Task.sleep(for: .milliseconds(300))

            #expect(state.hasArchive, "a stale cancel wiped the archive")
            #expect(!state.entries.isEmpty, "a stale cancel cleared the entries")
            #expect(
                state.url?.lastPathComponent == "zip_zipcrypto.zip",
                "wrong archive survived — got \(state.url?.lastPathComponent ?? "nothing")"
            )
        }

        /// A file the detector cannot place must say so, not fall through with a
        /// blank reason — the log line that started this was useless precisely
        /// because the message was thrown away.
        @Test func unrecognisedFileReportsWhy() async throws {
            let dir = try tempDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let bogus = dir.appendingPathComponent("not-an-archive.bin")
            try Data(repeating: 0x5A, count: 4096).write(to: bogus)

            let state = manualState(engine: .`7zip`)
            state.open(url: bogus)
            try await state.openTask?.value

            let message = try #require(state.error, "no reason reported")
            #expect(message.localizedCaseInsensitiveContains("not-an-archive.bin"), "got \(message)")
        }
    }

    // MARK: - Cleanup after a failed extraction

    @MainActor struct ExtractionCleanupSafetyTests {

        /// The cleanup that removes a half-written file after a failed entry
        /// built its path from the archive's own entry name — which the archive
        /// controls. An entry called `../victim.txt` pointed that path outside
        /// the destination, so a failed extraction deleted a file the user never
        /// asked MacPacker to touch. A wrong password is enough to trigger it.
        ///
        /// Everything here lives in a directory the test creates and removes, so
        /// the only file ever at risk is the test's own.
        @Test func failedExtractionNeverDeletesOutsideTheDestination() async throws {
            let root = try tempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            let destination = root.appendingPathComponent("dest")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

            // Outside `destination`, but still inside the test's own root.
            let bystander = root.appendingPathComponent("victim.txt")
            try "do not delete me\n".write(to: bystander, atomically: true, encoding: .utf8)

            let url = fixture("zip_zipcrypto.zip")
            let engine = ArchiveXadEngine()
            let load = try await engine.loadArchive(url: url, passwordResolver: neverResolves)
            let real = try #require(load.items.values.first { $0.virtualPath == helloPath })

            // The same entry, but the archive claims a traversing path for it.
            let hostile = ArchiveItem(
                index: real.index,
                name: "victim.txt",
                virtualPath: "../victim.txt",
                type: .file,
                uncompressedSize: real.uncompressedSize
            )

            // No password, so the entry fails and the cleanup path runs.
            await #expect(throws: (any Error).self) {
                _ = try await engine.extract(
                    items: [hostile],
                    from: url,
                    to: destination,
                    passwordResolver: neverResolves
                )
            }

            #expect(
                FileManager.default.fileExists(atPath: bystander.path),
                "cleanup deleted a file outside the destination"
            )
        }

        /// The guard must not cost the cleanup its job: an ordinary failed entry
        /// inside the destination still gets removed.
        @Test func failedExtractionStillCleansUpInsideTheDestination() async throws {
            let destination = try tempDirectory()
            defer { try? FileManager.default.removeItem(at: destination) }

            let url = fixture("zip_zipcrypto.zip")
            let engine = ArchiveXadEngine()
            let load = try await engine.loadArchive(url: url, passwordResolver: neverResolves)
            let real = try #require(load.items.values.first { $0.virtualPath == helloPath })

            // Stand in for the truncated file XAD leaves behind.
            let leftover = destination.appendingPathComponent(helloPath)
            try "partial".write(to: leftover, atomically: true, encoding: .utf8)

            await #expect(throws: (any Error).self) {
                _ = try await engine.extract(
                    items: [real],
                    from: url,
                    to: destination,
                    passwordResolver: neverResolves
                )
            }

            #expect(
                FileManager.default.fileExists(atPath: leftover.path) == false,
                "the partial file inside the destination was left behind"
            )
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

        /// One window, two archives, two passwords: an encrypted zip holding an
        /// encrypted zip, opened in place. Each password is asked for once, for
        /// its own file, and never offered to the other — why the window keeps
        /// its passwords per file rather than one for the archive.
        @Test func aNestedArchiveKeepsItsOwnPassword() async throws {
            let dir = try tempDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            // the inner archive is the fixture, which `correctPassword` opens
            let outer = dir.appendingPathComponent("outer.zip")
            try SevenZipArchive.writeArchive(
                destination: outer,
                items: [
                    .addFile(archivePath: "inner.zip", diskPath: fixture("zip_aes256.zip")),
                    .addData(archivePath: "note.txt", data: Data("outer note".utf8)),
                ],
                options: .init(format: .zip, password: "outer secret"))

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let requests = RequestLog()
            state.passwordProvider = { request in
                await requests.record(request)
                return request.url.lastPathComponent == "outer.zip" ? "outer secret" : correctPassword
            }
            state.open(url: outer)
            try await state.openTask?.value

            // Opened in place, the inner archive is taken out of the outer first,
            // which takes the outer's password.
            let inner = try #require(state.entries.values.first { $0.name == "inner.zip" })
            try await state.openAsync(item: inner)
            let hello = try #require(state.entries.values.first { $0.name == helloPath })
            let note = try #require(state.entries.values.first { $0.name == "note.txt" })
            #expect(contents(of: try await state.extractToTemp(item: hello)) == helloContents)
            #expect(contents(of: try await state.extractToTemp(item: note)) == "outer note")
            // and both again, with nothing left to ask
            #expect(contents(of: try await state.extractToTemp(item: hello)) == helloContents)
            #expect(contents(of: try await state.extractToTemp(item: note)) == "outer note")

            #expect(await requests.seen == ["outer.zip@1", "inner.zip@1"])
        }

        /// An archive holding a text file and, as `inner`, an archive of its own
        /// holding another. Each takes its password from `passwords`, by name;
        /// the format follows the extension.
        private func nestedArchive(_ outer: String, holding inner: String, in dir: URL,
                                   passwords: [String: String]) throws -> URL {
            func format(_ name: String) -> CompressionOptions.Format { name.hasSuffix(".7z") ? .sevenZ : .zip }
            let innerURL = dir.appendingPathComponent(inner)
            try SevenZipArchive.writeArchive(
                destination: innerURL,
                items: [.addData(archivePath: "in \(inner).txt", data: Data("in \(inner)".utf8))],
                options: .init(format: format(inner), password: passwords[inner]))
            let outerURL = dir.appendingPathComponent(outer)
            try SevenZipArchive.writeArchive(
                destination: outerURL,
                items: [.addFile(archivePath: inner, diskPath: innerURL),
                        .addData(archivePath: "in \(outer).txt", data: Data("in \(outer)".utf8))],
                options: .init(format: format(outer), password: passwords[outer]))
            try FileManager.default.removeItem(at: innerURL)
            return outerURL
        }

        /// Two archives in two tabs — each tab a window with its own ArchiveState —
        /// and each holding an archive of its own: four archives, four passwords,
        /// used by turns. Each window asks for its own two, once each, and never
        /// offers one to another file, its own or the other window's.
        @Test func twoWindowsKeepTheirPasswordsApart() async throws {
            let dir = try tempDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let passwords = ["a.zip": "outer A", "a-inner.7z": "inner A",
                             "b.7z": "outer B", "b-inner.zip": "inner B"]
            let archives = [("a.zip", "a-inner.7z"), ("b.7z", "b-inner.zip")]

            var windows: [(state: ArchiveState, requests: RequestLog)] = []
            for (outer, inner) in archives {
                let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
                let requests = RequestLog()
                state.passwordProvider = { request in
                    await requests.record(request)
                    return passwords[request.url.lastPathComponent]
                }
                state.open(url: try nestedArchive(outer, holding: inner, in: dir, passwords: passwords))
                try await state.openTask?.value
                windows.append((state, requests))
            }

            // the nested archives open in place, one window after the other
            for ((outer, inner), window) in zip(archives, windows) {
                let nested = try #require(window.state.entries.values.first { $0.name == inner }, "\(outer)")
                try await window.state.openAsync(item: nested)
            }
            // then every file, twice, taking turns between the windows
            for _ in 1...2 {
                for ((outer, inner), window) in zip(archives, windows) {
                    for name in [inner, outer] {
                        let file = try #require(window.state.entries.values.first { $0.name == "in \(name).txt" })
                        #expect(contents(of: try await window.state.extractToTemp(item: file)) == "in \(name)",
                                "in \(name).txt")
                    }
                }
            }

            #expect(await windows[0].requests.seen == ["a.zip@1", "a-inner.7z@1"])
            #expect(await windows[1].requests.seen == ["b.7z@1", "b-inner.zip@1"])
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
            state.extract(items: [hello], to: try tempDirectory(), smart: false)

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
            state.extract(items: [hello], to: try tempDirectory(), smart: false)

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
            state.extract(items: [hello], to: try tempDirectory(), smart: false)

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

/// Which file each password request was for, and its attempt: `file@attempt`.
private actor RequestLog {
    private(set) var seen: [String] = []

    func record(_ request: ArchivePasswordRequest) {
        seen.append("\(request.url.lastPathComponent)@\(request.attempt)")
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

// MARK: - The password belongs to opening the archive

/// Mac file information — a Finder tag, a resource fork — rides along in a
/// hidden AppleDouble sidecar next to the file it describes, because no archive
/// format has a place for it. Extraction has to fold that sidecar back onto its
/// file and drop it; a sidecar left standing is both the metadata lost and a
/// `__MACOSX` folder the user never asked for.
///
/// XADMaster does that fold while it parses the archive, which is inside its
/// open call — so it needs the password *then*. MacPacker used to hand one over
/// only after something failed, which is always later, and the metadata of every
/// encrypted archive was quietly dropped (#246). The fix is to resolve the
/// password when the archive is opened, for every engine, so all of this is one
/// behaviour rather than a property of which engine ran.
extension AllCoreTests {
    struct PasswordAtOpenTests {

        /// An encrypted archive holding one tagged file, plus a plain second
        /// file so an off-by-one in entry numbering has something to land on.
        private func taggedArchive(
            _ format: CompressionOptions.Format,
            password: String = correctPassword,
            in dir: URL
        ) throws -> URL {
            let fm = FileManager.default
            let source = dir.appendingPathComponent("src-\(UUID().uuidString)")
            try fm.createDirectory(at: source.appendingPathComponent("folder"), withIntermediateDirectories: true)

            let tagged = source.appendingPathComponent("tagged.txt")
            try Data(taggedContents.utf8).write(to: tagged)
            setExtendedAttribute(tagName, Data(tagValue.utf8), at: tagged)

            let plain = source.appendingPathComponent("folder/plain.txt")
            try Data(plainContents.utf8).write(to: plain)

            let archive = dir.appendingPathComponent("tagged-\(UUID().uuidString).\(format.rawValue)")
            try SevenZipArchive.writeArchive(
                destination: archive,
                items: [
                    .addFile(archivePath: "tagged.txt", diskPath: tagged),
                    .addDirectory(archivePath: "folder", diskPath: source.appendingPathComponent("folder")),
                    .addFile(archivePath: "folder/plain.txt", diskPath: plain),
                ],
                options: .init(format: format, password: password))
            return archive
        }

        private static let formats: [CompressionOptions.Format] = [.zip, .sevenZ]

        /// The bug as reported: the file comes back, the Finder tag does not.
        @Test(arguments: ZipReader.allCases, formats)
        func anEncryptedArchiveKeepsItsFinderTag(_ reader: ZipReader, _ format: CompressionOptions.Format) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let archive = try taggedArchive(format, in: dir)

            let out = dir.appendingPathComponent("out")
            try await extractEverything(archive, with: reader, to: out, password: correctPassword)

            #expect(extendedAttribute(tagName, at: out.appendingPathComponent("tagged.txt"))
                    == Data(tagValue.utf8),
                    "the Finder tag through \(reader) on \(format.rawValue)")
        }

        /// The other half of a sidecar that never got folded: it lands on disk
        /// as an ordinary file, and the user gets the `__MACOSX` litter they
        /// know from unzipping a Mac archive on Windows.
        @Test(arguments: ZipReader.allCases, formats)
        func nothingLeavesASidecarOnDisk(_ reader: ZipReader, _ format: CompressionOptions.Format) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let archive = try taggedArchive(format, in: dir)

            let out = dir.appendingPathComponent("out")
            try await extractEverything(archive, with: reader, to: out, password: correctPassword)

            let written = (try? FileManager.default.subpathsOfDirectory(atPath: out.path)) ?? []
            #expect(!written.contains { $0.hasPrefix("__MACOSX") },
                    "sidecar litter through \(reader) on \(format.rawValue): \(written)")
        }

        /// And the same sidecar must not reach the file list either — the window
        /// would show a `__MACOSX` folder for an encrypted archive that is not
        /// there when the same archive carries no password.
        @Test(arguments: ZipReader.allCases, formats)
        func theListingHidesSidecars(_ reader: ZipReader, _ format: CompressionOptions.Format) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let archive = try taggedArchive(format, in: dir)

            let loaded = try await reader.engine.loadArchive(
                url: archive, passwordResolver: { _ in correctPassword })
            let paths = loaded.items.values.compactMap(\.virtualPath)

            #expect(!paths.contains { $0.hasPrefix("__MACOSX") },
                    "listing through \(reader) on \(format.rawValue): \(paths.sorted())")
            #expect(loaded.isEncrypted, "through \(reader) on \(format.rawValue)")
        }

        /// The behaviour change that makes the rest possible, and the reason it
        /// is worth asserting on its own: the prompt belongs to opening the
        /// archive, not to the first thing that fails. Both engines, so the
        /// engine setting cannot change when the user is asked.
        @Test(arguments: ZipReader.allCases, formats)
        func openingAnEncryptedArchiveAsksForThePassword(_ reader: ZipReader, _ format: CompressionOptions.Format) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let archive = try taggedArchive(format, in: dir)

            let answers = PasswordAnswers.always(correctPassword)
            _ = try await reader.engine.loadArchive(url: archive, passwordResolver: answers.resolver)

            #expect(await answers.callCount > 0,
                    "no password was asked for when opening \(format.rawValue) with \(reader)")
        }

        /// An unencrypted archive must not start asking. The prompt appearing on
        /// every open would be the obvious way to get the above wrong.
        @Test(arguments: ZipReader.allCases, formats)
        func openingAPlainArchiveAsksForNothing(_ reader: ZipReader, _ format: CompressionOptions.Format) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let archive = dir.appendingPathComponent("plain.\(format.rawValue)")
            try SevenZipArchive.writeArchive(
                destination: archive,
                items: [.addData(archivePath: "a.txt", data: Data(plainContents.utf8))],
                options: .init(format: format))

            let answers = PasswordAnswers.always(correctPassword)
            _ = try await reader.engine.loadArchive(url: archive, passwordResolver: answers.resolver)

            #expect(await answers.callCount == 0,
                    "\(reader) asked for a password on a plain \(format.rawValue)")
        }

        /// Nobody to ask is not an error. A Quick Look preview and Finder's
        /// "Extract Here" build their state without a prompt, and an encrypted
        /// archive still lists the names it will show without a password — that
        /// is what the preview shows. Only extracting may fail.
        @Test(arguments: ZipReader.allCases, formats)
        func withNobodyToAskTheListingStillWorks(_ reader: ZipReader, _ format: CompressionOptions.Format) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let archive = try taggedArchive(format, in: dir)

            let loaded = try await reader.engine.loadArchive(url: archive, passwordResolver: neverResolves)
            let paths = loaded.items.values.compactMap(\.virtualPath)

            #expect(paths.contains("tagged.txt"), "through \(reader) on \(format.rawValue): \(paths.sorted())")
            #expect(loaded.isEncrypted, "through \(reader) on \(format.rawValue)")
        }

        /// A wrong password at open and the right one afterwards.
        ///
        /// Worth its own test because of how XADMaster numbers entries: without a
        /// working password the sidecars it could not fold stay in the listing as
        /// entries of their own, so the archive has more entries, at different
        /// indices, than the same archive opened with the password. An extraction
        /// that remembered the first numbering would hand back the wrong files.
        @Test(arguments: ZipReader.allCases, formats)
        func aWrongPasswordFirstStillExtractsTheRightFiles(_ reader: ZipReader, _ format: CompressionOptions.Format) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let archive = try taggedArchive(format, in: dir)

            let answers = PasswordAnswers("wrong", correctPassword, correctPassword,
                                          correctPassword, correctPassword, correctPassword)
            let engine = reader.engine
            let loaded = try await engine.loadArchive(url: archive, passwordResolver: answers.resolver)

            let out = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            _ = try await engine.extract(items: Array(loaded.items.values), from: archive,
                                         to: out, passwordResolver: answers.resolver)

            #expect(contents(of: out.appendingPathComponent("tagged.txt")) == taggedContents,
                    "through \(reader) on \(format.rawValue)")
            #expect(contents(of: out.appendingPathComponent("folder/plain.txt")) == plainContents,
                    "through \(reader) on \(format.rawValue)")
        }

        /// A 7z that encrypts its file names cannot be listed at all without the
        /// password, so this is the case that only works if the password reaches
        /// the library at open time. XADMaster used to be unable to open these —
        /// the "related" half of #246.
        @Test(arguments: ZipReader.allCases)
        func aHeaderEncrypted7zOpens(_ reader: ZipReader) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let archive = dir.appendingPathComponent("names.7z")
            try SevenZipArchive.writeArchive(
                destination: archive,
                items: [.addData(archivePath: "secret.txt", data: Data(plainContents.utf8))],
                options: .init(format: .sevenZ, password: correctPassword, encryptFileNames: true))

            let engine = reader.engine
            let loaded = try await engine.loadArchive(
                url: archive, passwordResolver: { _ in correctPassword })
            #expect(loaded.items.values.compactMap(\.virtualPath).contains("secret.txt"), "through \(reader)")

            let out = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            _ = try await engine.extract(items: Array(loaded.items.values), from: archive,
                                         to: out, passwordResolver: { _ in correctPassword })
            #expect(contents(of: out.appendingPathComponent("secret.txt")) == plainContents, "through \(reader)")
        }
    }
}

/// The attribute Finder stores a tag in, and a value to look for. Any extended
/// attribute would do — this is the one a user can actually see.
private let tagName = "com.apple.metadata:_kMDItemUserTags"
private let tagValue = "Important"
private let taggedContents = "tagged file\n"
private let plainContents = "plain file\n"
