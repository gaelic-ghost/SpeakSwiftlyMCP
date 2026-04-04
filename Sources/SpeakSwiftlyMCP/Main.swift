import Foundation

// MARK: - Entry Point

@main
enum SpeakSwiftlyMCPMain {
    static func main() {
        fputs("\(SpeakSwiftlyMCPDeprecation.message)\n", stderr)
        fputs("See \(SpeakSwiftlyMCPDeprecation.replacementReadmePath) for the maintained replacement.\n", stderr)
        exit(EXIT_FAILURE)
    }
}
