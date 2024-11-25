//
//  Package.swift
//  TriggerWordFramework
//
//  Created by Luke Zautke on 6/11/25.
//


// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TriggerWordFramework",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "TriggerWordFramework",
            targets: ["TriggerWordFramework"]
        ),
    ],
    targets: [
        .target(
            name: "TriggerWordFramework",
            path: "Sources/TriggerWordFramework",
            publicHeadersPath: "."
        )
    ]
)