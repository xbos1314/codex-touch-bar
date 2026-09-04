import Foundation

public struct CodexQuotaSnapshot: Equatable, Sendable {
    public var planType: String?
    public var mainUsedPercent: Int?
    public var mainResetsAt: Date?
    public var availableResetCount: Int?
    public var availableResetExpiresAt: Date?

    public init(
        planType: String?,
        mainUsedPercent: Int?,
        mainResetsAt: Date?,
        availableResetCount: Int?,
        availableResetExpiresAt: Date?
    ) {
        self.planType = planType
        self.mainUsedPercent = mainUsedPercent
        self.mainResetsAt = mainResetsAt
        self.availableResetCount = availableResetCount
        self.availableResetExpiresAt = availableResetExpiresAt
    }

    public static let unavailable = CodexQuotaSnapshot(
        planType: nil,
        mainUsedPercent: nil,
        mainResetsAt: nil,
        availableResetCount: nil,
        availableResetExpiresAt: nil
    )
}
