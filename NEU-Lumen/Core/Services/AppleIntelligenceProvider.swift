import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleIntelligenceProvider {
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability { return model.supportsLocale(Locale(identifier: "zh_CN")) }
        }
        #endif
        return false
    }

    static func summarize(_ input: CampusIntelligenceInput) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), available {
            let session = LanguageModelSession(model: .default, instructions: input.instructions)
            let response = try await session.respond(to: "以下JSON为待总结的资料：\n" + input.payload,
                generating: CampusGeneratedSummary.self, options: GenerationOptions(maximumResponseTokens: 384))
            try Task.checkCancellation()
            return response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw CancellationError()
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct CampusGeneratedSummary {
    @Guide(description: "仅根据资料生成的简短中文摘要，不加入新事实")
    var text: String
}
#endif
