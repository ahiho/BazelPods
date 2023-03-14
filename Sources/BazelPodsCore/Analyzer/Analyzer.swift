//
//  Analyzer.swift
//  CompilerCore
//
//  Created by Sergey Khliustin on 08.02.2023.
//

import Foundation

public struct Analyzer {
    private let platform: Platform
    private let spec: PodSpec
    private let subspecs: [PodSpec]
    private let options: BuildOptions

    let targetName: TargetName

    var baseInfo: BaseAnalyzer.Result
    var sourcesInfo: SourcesAnalyzer.Result
    var resourcesInfo: ResourcesAnalyzer.Result
    var sdkDepsInfo: SdkDependenciesAnalyzer.Result
    var vendoredDepsInfo: VendoredDependenciesAnalyzer.Result
    var podDepsInfo: PodDependenciesAnalyzer.Result
    var buildSettingsInfo: BuildSettingsAnalyzer.Result

    var podDependencies: [String] {
        return podDepsInfo.dependencies.map({
            targetName.podDependency($0, options: options)
        })
    }

    public init(platform: Platform,
                spec: PodSpec,
                subspecs: [PodSpec],
                options: BuildOptions) throws {
        self.platform = platform
        self.spec = spec
        self.subspecs = subspecs
        self.options = options
        self.targetName = TargetName(platform: platform, platformSuffix: options.platforms.count > 1)

        baseInfo = try BaseAnalyzer(platform: platform,
                                    spec: spec,
                                    subspecs: subspecs,
                                    options: options).run()
        sourcesInfo = SourcesAnalyzer(platform: platform,
                                      spec: spec,
                                      subspecs: subspecs,
                                      options: options).result
        resourcesInfo = ResourcesAnalyzer(platform: platform,
                                          spec: spec,
                                          subspecs: subspecs,
                                          options: options).result
        sdkDepsInfo = SdkDependenciesAnalyzer(platform: platform,
                                              spec: spec,
                                              subspecs: subspecs,
                                              options: options).result
        vendoredDepsInfo = VendoredDependenciesAnalyzer(platform: platform,
                                                        spec: spec,
                                                        subspecs: subspecs,
                                                        options: options).result
        podDepsInfo = PodDependenciesAnalyzer(platform: platform,
                                              spec: spec,
                                              subspecs: subspecs,
                                              options: options,
                                              targetName: targetName).result
        buildSettingsInfo = BuildSettingsAnalyzer(platform: platform,
                                                  spec: spec,
                                                  subspecs: subspecs,
                                                  options: options).result
    }

    public mutating func patch(_ patch: Patch) {
        patch.run(base: &baseInfo,
                  sources: &sourcesInfo,
                  resources: &resourcesInfo,
                  sdkDeps: &sdkDepsInfo,
                  vendoredDeps: &vendoredDepsInfo,
                  podDeps: &podDepsInfo,
                  buildSettings: &buildSettingsInfo)
    }
}