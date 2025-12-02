//
//  Breadcrumb.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.10.23.
//

import Foundation

@MainActor
class Breadcrumbs: ObservableObject {
    @Published var completePathArray: [String] = []
    @Published var completePath: String?
    
    /// Default constructor
    init () {
        startObserver()
    }
    
    /// Starts all observers
    func startObserver() {
        NotificationCenter.default.addObserver(forName: Notification.Name("Breadcrumbs.update"), object: nil, queue: nil) { notification in
            if let names = notification.object as? [String] {
                Task { @MainActor in
                    self.completePathArray = names
                    self.completePath = names.joined(separator: "/")
                }
            }
        }
    }
}
