//
//  UIImage+Extension.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 21/12/2023.
//

import SwiftUI

#if os(iOS) || os(visionOS)
extension UIImage {
    func convertImageToBase64String() -> String {
        return self.jpegData(compressionQuality: 1)?.base64EncodedString() ?? ""
    }
    
    func aspectFittedToHeight(_ newHeight: CGFloat) -> UIImage {
        let scale = newHeight / self.size.height
        let newWidth = self.size.width * scale
        let newSize = CGSize(width: newWidth, height: newHeight)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    /// Fit the image so its longest side equals `maxDimension`, preserving
    /// aspect ratio. Handles portrait and landscape symmetrically. Images
    /// already smaller than `maxDimension` are returned unchanged (no upscale).
    func aspectFittedToMaxDimension(_ maxDimension: CGFloat) -> UIImage {
        let longest = max(self.size.width, self.size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: self.size.width * scale, height: self.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    /// High-fidelity JPEG used both for the in-app thumbnail AND for
    /// re-transmission to stateless (E2EE) agents on follow-up turns.
    ///
    /// Tunable: `maxDimension` is capped at 1568px (longest side) and quality
    /// at 0.85. This is well above what common vision encoders consume
    /// (e.g. Gemma 3's encoder is 896×896), so detail is preserved without
    /// paying for pixels the model will downsample away. Raise these if a
    /// future agent uses a higher-resolution encoder; lower them if E2EE
    /// payload size becomes a concern.
    func compressImageData() -> Data? {
        let resizedImage = self.aspectFittedToMaxDimension(1568)
        return resizedImage.jpegData(compressionQuality: 0.85)
    }
}
#elseif os(macOS)
extension NSImage {
    func convertImageToBase64String() -> String {
        guard let tiffRepresentation = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            return ""
        }
        return jpegData.base64EncodedString()
    }
    
    func aspectFittedToHeight(_ newHeight: CGFloat) -> NSImage {
        let scale = newHeight / self.size.height
        let newWidth = self.size.width * scale
        let newSize = NSSize(width: newWidth, height: newHeight)
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
    
    /// Fit the image so its longest side equals `maxDimension`, preserving
    /// aspect ratio. Handles portrait and landscape symmetrically. Images
    /// already smaller than `maxDimension` are returned unchanged (no upscale).
    func aspectFittedToMaxDimension(_ maxDimension: CGFloat) -> NSImage {
        let longest = max(self.size.width, self.size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = NSSize(width: self.size.width * scale, height: self.size.height * scale)
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
    
    /// High-fidelity JPEG used both for the in-app thumbnail AND for
    /// re-transmission to stateless (E2EE) agents on follow-up turns.
    ///
    /// Tunable: `maxDimension` is capped at 1568px (longest side) and quality
    /// at 0.85. This is well above what common vision encoders consume
    /// (e.g. Gemma 3's encoder is 896×896), so detail is preserved without
    /// paying for pixels the model will downsample away. Raise these if a
    /// future agent uses a higher-resolution encoder; lower them if E2EE
    /// payload size becomes a concern.
    func compressImageData() -> Data? {
        let resizedImage = self.aspectFittedToMaxDimension(1568)
        guard let tiffRepresentation = resizedImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
#endif
