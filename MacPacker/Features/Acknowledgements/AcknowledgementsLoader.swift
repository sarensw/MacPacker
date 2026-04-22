import Foundation

struct Acknowledgement: Identifiable, Decodable {
    let id = UUID()
    let lib: String
    let author: String
    let link: String
    let license: String
    let licenseText: String
    enum CodingKeys: String, CodingKey {
        case lib, author, link, license, licenseText
    }
}

final class AcknowledgementsLoader {
    static func load() -> [Acknowledgement] {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        do {
            return try PropertyListDecoder().decode([Acknowledgement].self, from: data)
        } catch {
            print("Failed to decode acknowledgements:", error)
            return []
        }
    }
}