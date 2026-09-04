public enum TouchBarRobotPetTone: Equatable, Sendable {
    case idle
    case thinking
    case running
    case approval
    case completed
    case failed
    case reading
    case selecting
}

public enum TouchBarRobotPetExpression: Equatable, Sendable {
    case neutral
    case blink
    case thinking
    case working
    case happy
    case failed
    case reading
    case selecting
}

public enum TouchBarRobotPetEyeShape: Equatable, Sendable {
    case circle
    case smallCircle
    case closedLine
    case happyArc
    case dimCircle
}

public enum TouchBarRobotPetMouthShape: Equatable, Sendable {
    case smile
    case flat
    case frown
}

public enum TouchBarRobotPetBodyShape: Equatable, Sendable {
    case roundedTv
    case cyberTv
}

public enum TouchBarRobotPetAntennaLayout: Equatable, Sendable {
    case centerFork
    case splitTop
}

public enum TouchBarRobotPetWalkDirection: Equatable, Sendable {
    case left
    case right
}

public enum TouchBarRobotPetSideModuleHighlight: Equatable, Sendable {
    case none
    case left
    case right
}

public struct TouchBarRobotPetFaceExpression: Equatable, Sendable {
    public var leftEye: TouchBarRobotPetEyeShape
    public var rightEye: TouchBarRobotPetEyeShape
    public var mouth: TouchBarRobotPetMouthShape

    public init(
        leftEye: TouchBarRobotPetEyeShape,
        rightEye: TouchBarRobotPetEyeShape,
        mouth: TouchBarRobotPetMouthShape
    ) {
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.mouth = mouth
    }
}

public struct TouchBarRobotPetStyle: Equatable, Sendable {
    public var headWidth: Double
    public var headHeight: Double
    public var cornerRadius: Double
    public var faceWidth: Double
    public var faceHeight: Double
    public var verticalOffset: Double
    public var hasFeet: Bool
    public var hasSideModules: Bool
    public var eyeDiameter: Double
    public var showsMouth: Bool
    public var showsFacePanel: Bool
    public var showsInnerScreen: Bool
    public var showsHeadHighlight: Bool
    public var usesLightSymbols: Bool
    public var antennaCount: Int
    public var usesTextSymbols: Bool
    public var sideModulesBlendWithBody: Bool
    public var sideModuleWidth: Double
    public var sideModuleHeight: Double
    public var sideModuleInnerOverlap: Double
    public var eyeHorizontalOffset: Double
    public var antennaHorizontalOffset: Double
    public var highlightedSideModule: TouchBarRobotPetSideModuleHighlight
    public var bodyShape: TouchBarRobotPetBodyShape
    public var antennaLayout: TouchBarRobotPetAntennaLayout
    public var faceExpression: TouchBarRobotPetFaceExpression
    public var tone: TouchBarRobotPetTone
    public var expression: TouchBarRobotPetExpression

    public init(
        headWidth: Double,
        headHeight: Double,
        cornerRadius: Double,
        faceWidth: Double,
        faceHeight: Double,
        verticalOffset: Double,
        hasFeet: Bool,
        hasSideModules: Bool,
        eyeDiameter: Double,
        showsMouth: Bool,
        showsFacePanel: Bool,
        showsInnerScreen: Bool,
        showsHeadHighlight: Bool,
        usesLightSymbols: Bool,
        antennaCount: Int,
        usesTextSymbols: Bool,
        sideModulesBlendWithBody: Bool,
        sideModuleWidth: Double,
        sideModuleHeight: Double,
        sideModuleInnerOverlap: Double,
        eyeHorizontalOffset: Double,
        antennaHorizontalOffset: Double,
        highlightedSideModule: TouchBarRobotPetSideModuleHighlight,
        bodyShape: TouchBarRobotPetBodyShape,
        antennaLayout: TouchBarRobotPetAntennaLayout,
        faceExpression: TouchBarRobotPetFaceExpression,
        tone: TouchBarRobotPetTone,
        expression: TouchBarRobotPetExpression
    ) {
        self.headWidth = headWidth
        self.headHeight = headHeight
        self.cornerRadius = cornerRadius
        self.faceWidth = faceWidth
        self.faceHeight = faceHeight
        self.verticalOffset = verticalOffset
        self.hasFeet = hasFeet
        self.hasSideModules = hasSideModules
        self.eyeDiameter = eyeDiameter
        self.showsMouth = showsMouth
        self.showsFacePanel = showsFacePanel
        self.showsInnerScreen = showsInnerScreen
        self.showsHeadHighlight = showsHeadHighlight
        self.usesLightSymbols = usesLightSymbols
        self.antennaCount = antennaCount
        self.usesTextSymbols = usesTextSymbols
        self.sideModulesBlendWithBody = sideModulesBlendWithBody
        self.sideModuleWidth = sideModuleWidth
        self.sideModuleHeight = sideModuleHeight
        self.sideModuleInnerOverlap = sideModuleInnerOverlap
        self.eyeHorizontalOffset = eyeHorizontalOffset
        self.antennaHorizontalOffset = antennaHorizontalOffset
        self.highlightedSideModule = highlightedSideModule
        self.bodyShape = bodyShape
        self.antennaLayout = antennaLayout
        self.faceExpression = faceExpression
        self.tone = tone
        self.expression = expression
    }
}

public enum TouchBarRobotPetDrawingPolicy {
    private static let completedVerticalOffsets: [Double] = [
        0, 0, 0, 0,
        0.2, 0.4, 0.6, 0.6,
        0.4, 0.2, 0, 0
    ]

    private static func blinkFaceExpression(for frameIndex: Int) -> TouchBarRobotPetFaceExpression {
        switch frameIndex % 36 {
        case 25, 27:
            return TouchBarRobotPetFaceExpression(leftEye: .smallCircle, rightEye: .smallCircle, mouth: .flat)
        case 26:
            return TouchBarRobotPetFaceExpression(leftEye: .closedLine, rightEye: .closedLine, mouth: .flat)
        default:
            return TouchBarRobotPetFaceExpression(leftEye: .circle, rightEye: .circle, mouth: .flat)
        }
    }

    private static func thinkingFaceExpression(for frameIndex: Int) -> TouchBarRobotPetFaceExpression {
        switch frameIndex % 18 {
        case 6, 8:
            return TouchBarRobotPetFaceExpression(leftEye: .circle, rightEye: .smallCircle, mouth: .flat)
        case 7:
            return TouchBarRobotPetFaceExpression(leftEye: .smallCircle, rightEye: .circle, mouth: .flat)
        default:
            return blinkFaceExpression(for: frameIndex)
        }
    }

    public static func style(
        for mood: TouchBarPetMood,
        frameIndex: Int,
        walkDirection: TouchBarRobotPetWalkDirection? = nil
    ) -> TouchBarRobotPetStyle {
        let safeFrame = max(0, frameIndex)
        let tone: TouchBarRobotPetTone
        let expression: TouchBarRobotPetExpression
        var verticalOffset: Double
        let faceExpression: TouchBarRobotPetFaceExpression
        var eyeHorizontalOffset: Double = 0
        var antennaHorizontalOffset: Double = 0
        var highlightedSideModule: TouchBarRobotPetSideModuleHighlight = .none

        switch mood {
        case .idle:
            tone = .idle
            expression = safeFrame % 36 == 26 ? .blink : .neutral
            verticalOffset = 0
            faceExpression = blinkFaceExpression(for: safeFrame)
            if let walkDirection {
                let stepOffsets: [Double] = [0, 0.45, 0.2, -0.25]
                verticalOffset = stepOffsets[safeFrame % stepOffsets.count]
                switch walkDirection {
                case .left:
                    eyeHorizontalOffset = -0.85
                    antennaHorizontalOffset = -0.55
                    highlightedSideModule = .left
                case .right:
                    eyeHorizontalOffset = 0.85
                    antennaHorizontalOffset = 0.55
                    highlightedSideModule = .right
                }
            }
        case .thinking:
            tone = .thinking
            expression = .thinking
            verticalOffset = [0, 0.1, 0.2, 0.3, 0.2, 0.1, 0, -0.1][safeFrame % 8]
            faceExpression = thinkingFaceExpression(for: safeFrame)
        case .running:
            tone = .running
            expression = .working
            verticalOffset = [0, 0.4, 0.8, 1.1, 0.8, 0.4, 0, -0.3, -0.5, -0.3][safeFrame % 10]
            faceExpression = blinkFaceExpression(for: safeFrame)
        case .approval:
            tone = .approval
            expression = .working
            verticalOffset = [0, 0.3, 0.6, 0.8, 0.6, 0.3, 0, -0.2][safeFrame % 8]
            faceExpression = blinkFaceExpression(for: safeFrame)
        case .completed:
            tone = .completed
            expression = .happy
            verticalOffset = completedVerticalOffsets[safeFrame % completedVerticalOffsets.count]
            faceExpression = blinkFaceExpression(for: safeFrame)
        case .failed:
            tone = .failed
            expression = .failed
            verticalOffset = -0.4
            faceExpression = blinkFaceExpression(for: safeFrame)
        case .reading:
            tone = .reading
            expression = .reading
            verticalOffset = 0
            faceExpression = blinkFaceExpression(for: safeFrame)
        case .selecting:
            tone = .selecting
            expression = .selecting
            verticalOffset = safeFrame % 2 == 0 ? 0.4 : 0
            faceExpression = blinkFaceExpression(for: safeFrame)
        }

        return TouchBarRobotPetStyle(
            headWidth: 34,
            headHeight: 20,
            cornerRadius: 3.5,
            faceWidth: 28,
            faceHeight: 14,
            verticalOffset: verticalOffset,
            hasFeet: false,
            hasSideModules: true,
            eyeDiameter: 7.2,
            showsMouth: false,
            showsFacePanel: false,
            showsInnerScreen: false,
            showsHeadHighlight: false,
            usesLightSymbols: true,
            antennaCount: 2,
            usesTextSymbols: false,
            sideModulesBlendWithBody: true,
            sideModuleWidth: 3.2,
            sideModuleHeight: 7,
            sideModuleInnerOverlap: 0,
            eyeHorizontalOffset: eyeHorizontalOffset,
            antennaHorizontalOffset: antennaHorizontalOffset,
            highlightedSideModule: highlightedSideModule,
            bodyShape: .cyberTv,
            antennaLayout: .splitTop,
            faceExpression: faceExpression,
            tone: tone,
            expression: expression
        )
    }
}
