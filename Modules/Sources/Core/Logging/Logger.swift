//
//  Logger.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 04.09.25.
//

import TailBeatKit

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
    
    var tailBeatLevel: TailBeatLogLevel {
        switch self {
        case .Trace: return .Trace
        case .Debug: return .Debug
        case .Info: return .Info
        case .Warning: return .Warning
        case .Error: return .Error
        case .Fatal: return .Fatal
        }
    }
}

protocol LoggerSink {
    func log(level: LogLevel, _ message: String, file: String, function: String, line: Int)
    func debug(_ message: String, file: String, function: String, line: Int)
    func info(_ message: String, file: String, function: String, line: Int)
    func warning(_ message: String, file: String, function: String, line: Int)
    func error(_ message: String, file: String, function: String, line: Int)
}

class TailBeatSink: LoggerSink {
    func log(level: LogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        TailBeat.logger.log(level: level.tailBeatLevel, message, file: file, function: function, line: line)
        #endif
    }
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .Debug, message, file: file, function: function, line: line)
    }
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .Info, message, file: file, function: function, line: line)
    }
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .Warning, message, file: file, function: function, line: line)
    }
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .Error, message, file: file, function: function, line: line)
    }
}

class Logger {
    nonisolated(unsafe) private static var initialized: Bool = false
    nonisolated(unsafe) private static var sinks: [LoggerSink] = []
    
    static func initialize() {
        guard !Self.initialized else { return }
        
        Self.initialized = true
    }
    
    static func start() {
        sinks.append(TailBeatSink())
        
        initialize()
    }
    
    static func log(
        level: LogLevel = .Debug,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
    ) {
        initialize()
        
        for sink in sinks {
            sink.log(level: level, "\(message)", file: file, function: function, line: line)
        }
    }
    
    static func debug(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
    ) {
        Logger.log(
            level: .Debug,
            message,
            file: file,
            function: function,
            line: line
        )
    }
    
    static func info(
        _ message: String,
        file: String = #file,
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
        file: String = #file,
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
        file: String = #file,
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
    
    static func error(
        _ message: any Error,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
    ) {
        Logger.log(
            level: .Error,
            message.localizedDescription,
            file: file,
            function: function,
            line: line
        )
    }
}
