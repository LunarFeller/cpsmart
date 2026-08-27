import Foundation

@main
private struct CoreTestRunner {
    static func main() throws {
        try CoreTestSupport.runLegacySuite()
        print("All cpsmart core tests passed.")
    }
}
