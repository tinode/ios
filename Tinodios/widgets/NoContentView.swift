//
//  NoContentView.swift
//  Tinodios
//
//  Copyright © 2025 Tinode LLC. All rights reserved.
//
// An attempt to recreate UIContentUnavailableView for older iOS versions.
// This can be deleted when the minimum supported version reached 17.

import SwiftUI

enum ContentOptions {
    case messages
    case contacts

    var icon: String {
        return self == .messages ? "bubble.left" : "person.crop.circle"
    }

    var text: String {
        return self == .messages ? "No messages here" : "No contacts here"
    }
}

struct NoContentView: View {
    @State private var state: ContentOptions

    init(_ initialState: ContentOptions) {
        state = initialState
    }

    var body: some View {
        VStack{
            Image(systemName: state.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48, alignment: .center)
                .foregroundColor(.secondary)
            Text(state.text)
                .font(.title3)
        }
        .padding()
    }
}

#Preview {
    NoContentView(.messages)
}
