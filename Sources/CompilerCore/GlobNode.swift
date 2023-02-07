//
//  GlobNode.swift
//  PodToBUILD
//
//  Created by Jerry Marino on 05/21/18.
//  Copyright © 2020 Pinterest Inc. All rights reserved.
//

import Foundation

public struct GlobNode: StarlarkConvertible {
    // Bazel Glob function: glob(include, exclude=[], exclude_directories=1)
    public let include: [Either<[String], GlobNode>]
    public let exclude: [Either<[String], GlobNode>]
    public let excludeDirectories: Bool = true
    static let emptyArg: Either<[String], GlobNode>
        = Either.left([String]())

    public init(include: [String] = [], exclude: [String] = []) {
        self.init(include: [.left(include.sorted())], exclude: [.left(exclude.sorted())])
    }

    public init(include: Either<[String], GlobNode>, exclude: Either<[String], GlobNode>) {
        self.init(include: [include], exclude: [exclude])
    }

    public init(include: [Either<[String], GlobNode>] = [], exclude: [Either<[String], GlobNode>] = []) {
        // Upon allocation, form the most simple version of the glob
        self.include = include.simplify()
        self.exclude = exclude.simplify()
    }

    func map(_ transform: (String) -> String) -> GlobNode {
        return GlobNode(include: include.map({ $0.map(transform) }), exclude: exclude.map({ $0.map(transform) }))
    }

    func absolutePaths(_ options: BuildOptions) -> GlobNode {
        return map({ options.podTargetAbsoluteRoot.appendingPath($0) })
    }

    public func toStarlark() -> StarlarkNode {
        // An empty glob doesn't need to be rendered
        guard isEmpty == false else {
            return .empty
        }

        let include = self.include
        let exclude = self.exclude
        let includeArgs: [StarlarkFunctionArgument] = [
            .basic(include.reduce(StarlarkNode.empty) {
                $0 .+. $1.toStarlark()
            })
        ]

        // If there's no excludes omit the argument
        let excludeArgs: [StarlarkFunctionArgument] = exclude.isEmpty ? [] : [
            .named(name: "exclude", value: exclude.reduce(StarlarkNode.empty) {
                $0 .+. $1.toStarlark()
            })
        ]

        // Omit the default argument for exclude_directories
        let dirArgs: [StarlarkFunctionArgument] = self.excludeDirectories ? [] : [
            .named(name: "exclude_directories",
                   value: .int(self.excludeDirectories ? 1 : 0))
        ]

        return .functionCall(name: "glob",
                arguments: includeArgs + excludeArgs + dirArgs)
    }
}

extension Either: Equatable where T == [String], U == GlobNode {
    public static func == (lhs: Either, rhs: Either) -> Bool {
        if case let .left(lhsL) = lhs, case let .left(rhsL) = rhs {
            return lhsL == rhsL
        }
        if case let .right(lhsR) = lhs, case let .right(rhsR) = rhs {
            return lhsR == rhsR
        }
        if lhs.isEmpty && rhs.isEmpty {
            return true
        }
        return false
    }

    public func map(_ transform: (String) -> String) -> Either<[String], GlobNode> {
        switch self {
        case let .left(setVal):
            return .left(setVal.map(transform))
        case let .right(globVal):
            return .right(GlobNode(
                include: globVal.include.map {
                    $0.map(transform)
                }, exclude: globVal.exclude.map {
                    $0.map(transform)
                }
            ))
        }
    }

    public func compactMapInclude(_ transform: (String) -> String?) -> Either<[String], GlobNode> {
        switch self {
        case let .left(setVal):
            return .left(setVal.compactMap(transform))
        case let .right(globVal):
            let inc = globVal.include.compactMap({
                    $0.compactMapInclude(transform)
                })
            return .right(GlobNode(
                include: inc, exclude: globVal.exclude))
        }
    }

}

extension Array where Iterator.Element == Either<[String], GlobNode> {
    var isEmpty: Bool {
        return self.allSatisfy {
            $0.isEmpty
        }
    }

    public func simplify() -> [Either<[String], GlobNode>] {
        // First simplify the elements and then filter the empty elements
        return self
            .map { $0.simplify() }
            .filter { !$0.isEmpty }
    }
}

extension Either where T == [String], U == GlobNode {
    var isEmpty: Bool {
        switch self {
        case let .left(val):
            return val.isEmpty
        case let .right(val):
            return val.isEmpty
        }
    }

    public func simplify() -> Either<[String], GlobNode> {
        // Recursivly simplfies the globs
        switch self {
        case let .left(val):
            // Base case, this is as simple as it gets
            return .left(val)
        case let .right(val):
            let include = val.include.simplify()
            let exclude = val.exclude.simplify()
            if exclude.isEmpty {
                // When there is no excludes we can do the following:
                // 1. smash all sets into a single set
                // 2. return a set if there are no other globs
                // 3. otherwise, return a simplified glob with 1 set and
                // remaining globs
                var setAccum: [String] = []
                let remainingGlobs = include
                    .reduce(into: [Either<[String], GlobNode>]()) { accum, next in
                    switch next {
                    case let .left(val):
                        setAccum = setAccum <> val
                    case let .right(val):
                        if !val.isEmpty {
                            accum.append(next)
                        }
                    }
                }

                // If there are no remaining globs, simplify to a set
                if remainingGlobs.count == 0 {
                    return .left(setAccum)
                } else {
                    return .right(GlobNode(include: remainingGlobs + [.left(setAccum)]))
                }
            } else {
                return .right(GlobNode(include: include, exclude: exclude))
            }
        }
    }
}

extension GlobNode: Equatable {
    public static func == (lhs: GlobNode, rhs: GlobNode) -> Bool {
        return lhs.include == rhs.include
            && lhs.exclude == rhs.exclude
    }
}

extension GlobNode: EmptyAwareness {
    public var isEmpty: Bool {
        // If the include is the same as the exclude then it's empty
        return self.include.isEmpty || self.include == self.exclude
    }

    public static var empty: GlobNode {
        return GlobNode(include: [String]())
    }
}

extension GlobNode: Monoid {
    public static func <> (_: GlobNode, _: GlobNode) -> GlobNode {
        // Currently, there is no way to implement this reasonablly
        fatalError("cannot combine GlobNode ( added for AttrSet )")
    }
}

extension GlobNode {
    /// Evaluates the glob for all the sources on disk
    public func sourcesOnDisk(_ options: BuildOptions) -> Set<String> {
        let absoluteSelf = self.absolutePaths(options)
        let includedFiles = absoluteSelf.include.reduce(into: Set<String>()) { accum, next in
            switch next {
            case .left(let setVal):
                 setVal.forEach { podGlob(pattern: $0).forEach { accum.insert($0) } }
            case .right(let globVal):
                 globVal.sourcesOnDisk(options).forEach { accum.insert($0) }
            }
        }

        let excludedFiles = absoluteSelf.exclude.reduce(into: Set<String>()) { accum, next in
            switch next {
            case .left(let setVal):
                 setVal.forEach { podGlob(pattern: $0).forEach { accum.insert($0) } }
            case .right(let globVal):
                 globVal.sourcesOnDisk(options).forEach { accum.insert($0) }
            }
        }
        return includedFiles.subtracting(excludedFiles)
    }

    func hasSourcesOnDisk(_ options: BuildOptions) -> Bool {
        return sourcesOnDisk(options).count > 0
    }
}