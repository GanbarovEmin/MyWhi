// HDTokens.swift
// Cohere spacing + radius tokens.
// Reference: DESIGN-cohere (1).md — "Spacing System" and "Radius Scale".
//
// Usage:
//   VStack(spacing: HDSpacing.lg.rawValue) { ... }
//   .padding(.horizontal, HDSpacing.xl.rawValue)
//   .background(.white, in: RoundedRectangle(cornerRadius: HDRadius.lg.rawValue))

import CoreGraphics

/// 8px base with named exceptions. `rawValue` is in points.
enum HDSpacing: CGFloat, CaseIterable {
    case xxs = 2
    case xs  = 6
    case sm  = 8
    case md  = 12
    case lg  = 16
    case xl  = 24
    case xxl = 32
    case section = 80
}

/// Cohere radius scale. `rawValue` is in points.
enum HDRadius: CGFloat, CaseIterable {
    case xs   = 4
    case sm   = 8
    case md   = 16
    case lg   = 22
    case xl   = 30
    case pill = 32
    case full = 9999
}