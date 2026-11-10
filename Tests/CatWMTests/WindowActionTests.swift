@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Suite struct WindowActionTests {
    @Test func namesAndAliasesAreUniqueAndResolve() {
        let names = WindowActions.all.flatMap { [$0.name] + $0.aliases }
        #expect(Set(names).count == names.count)
        for action in WindowActions.all {
            #expect(action.name == action.name.lowercased())
            for name in [action.name] + action.aliases {
                #expect(WindowActions.named(name)?.name == action.name)
            }
        }
    }

    @Test func everyPickerRowIsUniqueAndRunsAnAction() {
        let ids = Actions.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        let effects = Set(FocusEffect.all.map(\.dispatcher))
        for row in Actions.all where !effects.contains(row.dispatcher) {
            #expect(WindowActions.named(row.dispatcher) != nil, "\(row.title)")
        }
    }

    @Test func theRegistryFollowsTheCatalog() throws {
        let names = CommandRegistry.dispatchers.map(\.name)
        #expect(Array(names.prefix(WindowActions.all.count)) == WindowActions.all.map(\.name))
        for action in WindowActions.all {
            let command = try #require(CommandRegistry.command(named: action.name))
            #expect(command.group == action.group)
            #expect(command.summary == action.summary)
            #expect(command.access == action.access)
            #expect(command.args.map(\.name) == action.args.map(\.name))
            for alias in action.aliases { #expect(CommandRegistry.command(named: alias) == nil) }
        }
    }

    @Test func anUnknownDispatcherIsIgnored() {
        let manager = WindowManager(config: .parse(defaultText))
        var dispatched: [String] = []
        manager.onDispatch = { name, _, _ in dispatched.append(name) }
        manager.dispatch("nothing", "")
        #expect(WindowActions.named("nothing") == nil)
        #expect(dispatched == ["nothing"])
    }

    @Test func aHandlerRunsByNameAndByAlias() throws {
        let manager = WindowManager(config: .parse(defaultText))
        manager.corrections = [1: (target: .zero, count: 1)]
        try #require(WindowActions.named("retile")).run(ActionContext(manager: manager, arg: ""))
        #expect(manager.corrections.isEmpty)
        manager.corrections = [1: (target: .zero, count: 1)]
        manager.dispatch("reevaluate", " ")
        #expect(manager.corrections.isEmpty)
    }
}
