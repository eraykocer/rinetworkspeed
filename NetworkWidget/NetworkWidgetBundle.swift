//
//  NetworkWidgetBundle.swift
//  NetworkWidget
//
//  Created by Eray Koçer on 9.04.2026.
//

import WidgetKit
import SwiftUI

@main
struct NetworkWidgetBundle: WidgetBundle {
    var body: some Widget {
        NetworkWidgetControl()
        NetworkWidgetLiveActivity()
    }
}
