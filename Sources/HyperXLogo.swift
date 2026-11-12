import AppKit

/// Логотип HyperX «hX». Контур взят из Simple Icons (icons/hyperx.svg, CC0) и
/// пересчитан в координаты, где высота = 1, а начало — левый нижний угол (y вверх).
/// HyperX — товарный знак HP Inc. Проект неофициальный и с HP/HyperX не связан; логотип используется
/// только чтобы значок узнавался. По требованию правообладателя его можно заменить в одном месте — здесь.
enum HyperXLogo {
    /// Ширина / высота.
    static let aspect: CGFloat = 1.7736

    static func path(in rect: NSRect) -> NSBezierPath {
        let s = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        let path = NSBezierPath()
        path.windingRule = .nonZero
        path.move(to: p(1.6557, 0.9996))
        path.curve(to: p(1.6517, 0.9959), controlPoint1: p(1.6531, 1.0000), controlPoint2: p(1.6517, 0.9959))
        path.curve(to: p(1.3380, 0.5898), controlPoint1: p(1.5827, 0.8264), controlPoint2: p(1.4711, 0.6936))
        path.curve(to: p(0.8599, 0.7743), controlPoint1: p(1.1788, 0.6964), controlPoint2: p(1.0076, 0.7492))
        path.line(to: p(0.8974, 0.8994))
        path.line(to: p(0.7797, 0.8994))
        path.line(to: p(0.7469, 0.7890))
        path.curve(to: p(0.4765, 0.7884), controlPoint1: p(0.5904, 0.8033), controlPoint2: p(0.4804, 0.7887))
        path.curve(to: p(0.4686, 0.7842), controlPoint1: p(0.4702, 0.7879), controlPoint2: p(0.4685, 0.7864))
        path.curve(to: p(0.4748, 0.7811), controlPoint1: p(0.4689, 0.7811), controlPoint2: p(0.4748, 0.7811))
        path.curve(to: p(1.2400, 0.5207), controlPoint1: p(0.7869, 0.7572), controlPoint2: p(1.0420, 0.6490))
        path.curve(to: p(0.0114, 0.2178), controlPoint1: p(0.7329, 0.1977), controlPoint2: p(0.0114, 0.2178))
        path.curve(to: p(0.0003, 0.2130), controlPoint1: p(0.0023, 0.2180), controlPoint2: p(0.0004, 0.2164))
        path.curve(to: p(0.0086, 0.2079), controlPoint1: p(0.0000, 0.2079), controlPoint2: p(0.0086, 0.2079))
        path.curve(to: p(1.3548, 0.4398), controlPoint1: p(0.9235, 0.0951), controlPoint2: p(1.3207, 0.4142))
        path.curve(to: p(1.7617, 0.0068), controlPoint1: p(1.6268, 0.2317), controlPoint2: p(1.7617, 0.0068))
        path.curve(to: p(1.7695, 0.0010), controlPoint1: p(1.7642, 0.0031), controlPoint2: p(1.7668, 0.0000))
        path.curve(to: p(1.7710, 0.0088), controlPoint1: p(1.7736, 0.0024), controlPoint2: p(1.7710, 0.0088))
        path.curve(to: p(1.4407, 0.5113), controlPoint1: p(1.6926, 0.2341), controlPoint2: p(1.5742, 0.3958))
        path.curve(to: p(1.6580, 0.9910), controlPoint1: p(1.6507, 0.7148), controlPoint2: p(1.6566, 0.9720))
        path.curve(to: p(1.6558, 0.9996), controlPoint1: p(1.6588, 0.9993), controlPoint2: p(1.6573, 0.9995))
        path.close()
        path.move(to: p(0.3649, 0.8994))
        path.line(to: p(0.2679, 0.5758))
        path.line(to: p(0.3847, 0.5758))
        path.line(to: p(0.4817, 0.8994))
        path.close()
        path.move(to: p(0.4674, 0.7501))
        path.line(to: p(0.4511, 0.6949))
        path.line(to: p(0.7186, 0.6949))
        path.curve(to: p(0.6830, 0.5758), controlPoint1: p(0.7120, 0.6729), controlPoint2: p(0.6830, 0.5758))
        path.line(to: p(0.8006, 0.5758))
        path.line(to: p(0.8318, 0.6802))
        path.line(to: p(0.4674, 0.7501))
        path.close()
        return path
    }
}
