import Foundation
import Dispatch
import MatchInboxCLI

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "review-on-device" || arguments.first == "review-local" || arguments.first == "ideas" || arguments.first == "ideas-local" || arguments.first == "inbox-local" || arguments.first == "dump-local" || arguments.first == "import-local" {
    Task {
        do {
            if arguments.first == "import-local" {
                print(try MatchInboxCommand.runImportIntoLocalStore(arguments: arguments))
            } else if arguments.first == "inbox-local" {
                print(try MatchInboxCommand.runStoredInbox(arguments: arguments))
            } else if arguments.first == "dump-local" {
                print(try MatchInboxCommand.runStoredDump(arguments: arguments))
            } else if arguments.first == "ideas" {
                print(try await MatchInboxCommand.runIdeas(arguments: arguments))
            } else if arguments.first == "ideas-local" {
                print(try await MatchInboxCommand.runStoredIdeas(arguments: arguments))
            } else if arguments.first == "review-local" {
                print(try await MatchInboxCommand.runStoredOnDeviceReview(arguments: arguments))
            } else {
                print(try await MatchInboxCommand.runOnDeviceReview(arguments: arguments))
            }
        } catch {
            print("error: \(error)")
        }
        exit(0)
    }
    dispatchMain()
} else {
    do {
        print(try MatchInboxCommand.run(arguments: arguments))
    } catch {
        print("error: \(error)")
    }
}
