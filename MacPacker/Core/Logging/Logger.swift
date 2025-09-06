//
//  Logger.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 04.09.25.
//

class Dummy {
    func dummyFunc() {
        Logger.log("")
        Logger.info("")
        Logger.warning("")
        Logger.error("")
    }
}

enum LogLevel: Int {
    case Trace = 0
    case Debug = 1
    case Info = 2
    case Warning = 3
    case Error = 4
    case Fatal = 5
}

class Logger {
    private static var tailBeat: TailBeat?
    private static var initialized: Bool = false
    
    static func initialize() {
        guard !Self.initialized else { return }
        
        Self.tailBeat = TailBeat.logger.start(
            collectStdout: true
        )
        Self.initialized = true
    }
    
    static func start() {
        initialize()
    }
    
    static func log(
        level: LogLevel = .Debug,
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) {
        initialize()
        
        #if DEBUG
        tailBeat?.log(
            level: .Debug,
            "\(message)",
            file: file,
            function: function,
            line: line
        )
        #endif
    }
    
    static func info(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) {
        Logger.log(
            level: .Info,
            message,
            file: file,
            function: function,
            line: line
        )
    }
    
    static func warning(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) {
        Logger.log(
            level: .Warning,
            message,
            file: file,
            function: function,
            line: line
        )
    }
    
    static func error(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) {
        Logger.log(
            level: .Error,
            message,
            file: file,
            function: function,
            line: line
        )
    }
}
