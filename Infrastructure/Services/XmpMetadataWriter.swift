import Foundation

public struct XmpMetadataWriter {
    public static func writeXmpSidecar(for fileURL: URL, rating: Int, isTagged: Bool) {
        let xmpURL = fileURL.deletingPathExtension().appendingPathExtension("xmp")
        let label = isTagged ? "Tagged" : ""
        let ratingStr = "\(rating)"
        
        SecurityScopedBookmarkManager.shared.performAccessingSecurityScopedResource(at: fileURL.deletingLastPathComponent()) {
            let fileManager = FileManager.default
            var xmpContent = ""
            
            if fileManager.fileExists(atPath: xmpURL.path),
               let existingContent = try? String(contentsOf: xmpURL, encoding: .utf8) {
                xmpContent = existingContent
                
                // Update Rating
                if let ratingRange = xmpContent.range(of: "<xmp:Rating>") {
                    if let ratingEndRange = xmpContent.range(of: "</xmp:Rating>", range: ratingRange.upperBound..<xmpContent.endIndex) {
                        xmpContent.replaceSubrange(ratingRange.upperBound..<ratingEndRange.lowerBound, with: ratingStr)
                    }
                } else {
                    // Try to insert before </rdf:Description>
                    if let descCloseRange = xmpContent.range(of: "</rdf:Description>") {
                        xmpContent.insert(contentsOf: "   <xmp:Rating>\(ratingStr)</xmp:Rating>\n", at: descCloseRange.lowerBound)
                    } else if let descSelfCloseRange = xmpContent.range(of: "<rdf:Description"),
                              let selfCloseEndRange = xmpContent.range(of: "/>", range: descSelfCloseRange.upperBound..<xmpContent.endIndex) {
                        // Expand self-closing rdf:Description to full block
                        let attrs = xmpContent[descSelfCloseRange.lowerBound..<selfCloseEndRange.lowerBound]
                        let expanded = "\(attrs)>\n   <xmp:Rating>\(ratingStr)</xmp:Rating>\n  </rdf:Description>"
                        xmpContent.replaceSubrange(descSelfCloseRange.lowerBound...selfCloseEndRange.upperBound, with: expanded)
                    }
                }
                
                // Update Label
                if let labelRange = xmpContent.range(of: "<xmp:Label>") {
                    if let labelEndRange = xmpContent.range(of: "</xmp:Label>", range: labelRange.upperBound..<xmpContent.endIndex) {
                        xmpContent.replaceSubrange(labelRange.upperBound..<labelEndRange.lowerBound, with: label)
                    }
                } else {
                    // Try to insert before </rdf:Description>
                    if let descCloseRange = xmpContent.range(of: "</rdf:Description>") {
                        xmpContent.insert(contentsOf: "   <xmp:Label>\(label)</xmp:Label>\n", at: descCloseRange.lowerBound)
                    }
                }
            } else {
                // Create new
                xmpContent = """
                <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="XMP Core 6.0.0">
                 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                  <rdf:Description rdf:about=""
                    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                    xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">
                   <xmp:Rating>\(ratingStr)</xmp:Rating>
                   <xmp:Label>\(label)</xmp:Label>
                  </rdf:Description>
                 </rdf:RDF>
                </x:xmpmeta>
                """
            }
            
            do {
                try xmpContent.write(to: xmpURL, atomically: true, encoding: .utf8)
                LoggerManager.shared.log("Successfully wrote XMP sidecar for \(fileURL.lastPathComponent)", level: .info)
            } catch {
                LoggerManager.shared.log("Failed to write XMP sidecar: \(error.localizedDescription)", level: .error)
            }
        }
    }
    
    public static func readXmpSidecar(for fileURL: URL) -> (rating: Int, isTagged: Bool)? {
        let xmpURL = fileURL.deletingPathExtension().appendingPathExtension("xmp")
        
        return SecurityScopedBookmarkManager.shared.performAccessingSecurityScopedResource(at: fileURL.deletingLastPathComponent()) { () -> (rating: Int, isTagged: Bool)? in
            guard FileManager.default.fileExists(atPath: xmpURL.path) else { return nil }
            
            do {
                let content = try String(contentsOf: xmpURL, encoding: .utf8)
                
                var rating = 0
                if let range = content.range(of: "<xmp:Rating>"),
                   let endRange = content.range(of: "</xmp:Rating>", range: range.upperBound..<content.endIndex) {
                    let ratingStr = content[range.upperBound..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                    rating = Int(ratingStr) ?? 0
                }
                
                var isTagged = false
                if let range = content.range(of: "<xmp:Label>"),
                   let endRange = content.range(of: "</xmp:Label>", range: range.upperBound..<content.endIndex) {
                    let labelStr = content[range.upperBound..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                    isTagged = !labelStr.isEmpty && labelStr.lowercased() != "none"
                }
                
                return (rating, isTagged)
            } catch {
                LoggerManager.shared.log("Failed to read XMP sidecar for \(fileURL.lastPathComponent): \(error.localizedDescription)", level: .error)
                return nil
            }
        }
    }
}
