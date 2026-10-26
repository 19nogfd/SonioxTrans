import Foundation

@main
struct TokenAccumulatorCheck {
    static func main() {
        var accumulator = TokenAccumulator()
        let preview = accumulator.consume([
            ["text": "こん", "is_final": false, "translation_status": "original"],
            ["text": "你", "is_final": false, "translation_status": "translation"]
        ])
        precondition(preview.0 == "こん" && preview.1 == "你" && !preview.2)

        let final = accumulator.consume([
            ["text": "こんにちは", "is_final": true, "translation_status": "original"],
            ["text": "你好", "is_final": true, "translation_status": "translation"],
            ["text": "<end>", "is_final": true]
        ])
        precondition(final.0 == "こんにちは")
        precondition(final.1 == "你好")
        precondition(final.2)
        precondition(accumulator.take(previewOriginal: final.0, previewTranslation: final.1) == ("こんにちは", "你好"))
        print("Token accumulator checks passed")
    }
}
