//
//  FitMode.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import Foundation

enum FitMode: String, CaseIterable {
    case fitWindowToImage = "Fit window to image"
    case fitImageToWindow = "Fit image to window"
    case fitOnlyBigToWindow = "Fit only big images to window"
    case fitOnlyBigToDesktop = "Fit only big images to desktop"
    case doNotFit = "Do not fit anything"
}

