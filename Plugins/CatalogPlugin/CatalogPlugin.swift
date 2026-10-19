import PackagePlugin

@main
struct CatalogPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let script = context.package.directory.appending("Tools/generate-catalogs.py")
        let output = context.pluginWorkDirectory.appending("GalleryRegistry.swift")
        return [.buildCommand(displayName: "Collect control-owned gallery examples",
                              executable: Path("/usr/bin/python3"), arguments: [script.string, output.string],
                              inputFiles: [script] + target.sourceFiles(withSuffix: "swift").map(\.path),
                              outputFiles: [output])]
    }
}
