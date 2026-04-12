//
//  AvatarStore.swift
//  WeItems
//

import UIKit
import Combine

class AvatarStore: ObservableObject {
    static let shared = AvatarStore()
    
    @Published var avatarImage: UIImage?
    
    private var avatarURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("user_avatar.jpg")
    }
    
    private init() {
        avatarImage = loadFromDisk()
    }
    
    func saveAvatar(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: avatarURL, options: .atomic)
        avatarImage = image
    }
    
    private func loadFromDisk() -> UIImage? {
        guard FileManager.default.fileExists(atPath: avatarURL.path),
              let data = try? Data(contentsOf: avatarURL) else { return nil }
        return UIImage(data: data)
    }
}
