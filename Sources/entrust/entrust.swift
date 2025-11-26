import ArgumentParser
import Foundation

@main
struct Entrust: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "entrust",
        abstract: "Automate iOS development from JIRA/Linear to PR using Claude Code",
        version: "0.1.0",
        subcommands: [Setup.self, Run.self, Parallel.self, Status.self],
        defaultSubcommand: Run.self
    )
}
