import ArgumentParser
import Foundation

@main
struct Entrust: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "entrust",
        abstract: "Automate iOS development from JIRA/Linear ticket to PR",
        version: "1.0.0",
        subcommands: [Setup.self, Run.self, Status.self, Parallel.self],
        defaultSubcommand: Run.self
    )
}
