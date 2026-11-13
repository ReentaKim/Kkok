import CoreGraphics
import Foundation

/// 실행 취소 단위가 되는 편집 상태. 원본 이미지는 바뀌지 않고, 캔버스 범위와 주석만 바뀐다.
struct DocumentState: Codable, Equatable {
    /// 원본 이미지 픽셀 크기
    var imageSize: CGSize
    /// 결과물로 내보낼 범위(이미지 좌표). 자르기는 줄이고, 캔버스 넓히기는 이미지 밖으로 늘린다.
    var canvasRect: CGRect
    var annotations: [Annotation] = []

    init(imageSize: CGSize) {
        self.imageSize = imageSize
        self.canvasRect = CGRect(origin: .zero, size: imageSize)
    }

    /// 다음 숫자 스탬프 번호
    var nextStampNumber: Int {
        (annotations.filter { $0.kind == .stamp && $0.stamp == .number }.map(\.number).max() ?? 0) + 1
    }

    // MARK: 자르기 (FR-17)

    /// 고른 범위로 자른다. 현재 캔버스 안으로 제한하고, 너무 작으면 무시한다.
    mutating func crop(to r: CGRect) {
        let clipped = r.standardized.integral.intersection(canvasRect)
        guard !clipped.isNull, clipped.width >= 4, clipped.height >= 4 else { return }
        canvasRect = clipped
    }

    // MARK: 캔버스 넓히기 (FR-18)

    enum Edge: String, Codable { case top, bottom, left, right }

    /// 짧은 변의 25%(최소 40px)만큼 그쪽으로 넓힌다.
    mutating func expand(_ edge: Edge, minimum: CGFloat = 40) {
        let amount = max(minimum, (min(canvasRect.width, canvasRect.height) * 0.25).rounded())
        switch edge {
        case .top: canvasRect.origin.y -= amount; canvasRect.size.height += amount
        case .bottom: canvasRect.size.height += amount
        case .left: canvasRect.origin.x -= amount; canvasRect.size.width += amount
        case .right: canvasRect.size.width += amount
        }
    }

    /// 캔버스가 원본 이미지 밖으로 나간 부분이 있는지 (흰 배경을 칠해야 하는지)
    var needsBackground: Bool {
        !CGRect(origin: .zero, size: imageSize).contains(canvasRect)
    }
}
