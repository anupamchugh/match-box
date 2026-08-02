import Foundation
import Dispatch
import MatchInboxCLI

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "review-on-device" || arguments.first == "review-local" {
    Task {
        do {
            if arguments.first == "review-local" {
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
