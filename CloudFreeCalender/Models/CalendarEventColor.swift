import SwiftUI

enum CalendarEventColor: String, CaseIterable, Sendable {
    case blau   = "blau"
    case gruen  = "gruen"
    case orange = "orange"
    case rot    = "rot"
    case lila   = "lila"

    var label: String {
        switch self {
        case .blau:   return "Blau"
        case .gruen:  return "Grün"
        case .orange: return "Orange"
        case .rot:    return "Rot"
        case .lila:   return "Lila"
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var colors: [Color] {
        switch self {
        case .blau:   return [Color(hex: 0x2563eb), Color(hex: 0x7c3aed)]
        case .gruen:  return [Color(hex: 0x059669), Color(hex: 0x0284c7)]
        case .orange: return [Color(hex: 0xd97706), Color(hex: 0xdc2626)]
        case .rot:    return [Color(hex: 0xdc2626), Color(hex: 0x9333ea)]
        case .lila:   return [Color(hex: 0x7c3aed), Color(hex: 0xec4899)]
        }
    }

    var swatch: Color { colors[0] }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255
        let g = Double((hex >> 8)  & 0xff) / 255
        let b = Double( hex        & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }
}
