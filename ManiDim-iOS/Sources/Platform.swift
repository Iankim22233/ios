import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension Color {
    /// sRGB components (0...1).
    func rgbTuple() -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) { return (Double(r), Double(g), Double(b)) }
        return (0.5, 0.5, 0.5)
    }
}

/// UIKit document pickers, callable from non-view code (replaces NSOpenPanel / NSSavePanel).
enum FilePicker {
    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let done: (URL?) -> Void
        static var live: [Delegate] = []
        init(_ done: @escaping (URL?) -> Void) { self.done = done }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls.first) }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { finish(nil) }
        private func finish(_ u: URL?) { done(u); Delegate.live.removeAll { $0 === self } }
    }

    private static func top() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var v = scene?.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene?.windows.first?.rootViewController
        while let p = v?.presentedViewController { v = p }
        return v
    }

    /// Picks a file and hands back a local copy that stays valid after the call.
    static func open(types: [UTType], completion: @escaping (URL?) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        let d = Delegate(completion)
        Delegate.live.append(d)
        picker.delegate = d
        picker.allowsMultipleSelection = false
        top()?.present(picker, animated: true)
    }

    /// Exports an existing temp file via the system "Save to Files" sheet.
    static func export(_ file: URL, completion: @escaping (Bool) -> Void) {
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        let d = Delegate { completion($0 != nil) }
        Delegate.live.append(d)
        picker.delegate = d
        top()?.present(picker, animated: true)
    }
}
