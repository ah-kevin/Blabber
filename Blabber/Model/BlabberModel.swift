import Foundation
import CoreLocation
import Combine
import UIKit

/// The app model that communicates with the server.
@MainActor
class BlabberModel: ObservableObject {
  var username = ""
  var urlSession = URLSession.shared

  nonisolated init() {
  }

  /// Current live updates
  @Published var messages: [Message] = []

  /// Shares the current user's address in chat.
  func shareLocation() async throws {
  }

  /// Does a countdown and sends the message.
  func countdown(to message: String) async throws {
    guard !message.isEmpty else { return }
  }

  /// Start live chat updates
  func chat() async throws {
    guard
      let query = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
      let url = URL(string: "http://localhost:8080/chat/room?\(query)")
      else {
      throw "Invalid username"
    }

    let (stream, response) = try await liveURLSession.bytes(from: url, delegate: nil)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw "The server responded with an error."
    }

    print("Start live updates")

    try await withTaskCancellationHandler(operation: {
      try await readMessages(stream: stream)
    }, onCancel: {
      print("End live updates")
      Task { @MainActor in
        messages = []
      }
    })
  }

  /// Reads the server chat stream and updates the data model.
  private func readMessages(stream: URLSession.AsyncBytes) async throws {
  }

  /// Sends the user's message to the chat server
  func say(_ text: String, isSystemMessage: Bool = false) async throws {
    guard
      !text.isEmpty,
      let url = URL(string: "http://localhost:8080/chat/say")
    else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(
      Message(id: UUID(), user: isSystemMessage ? nil : username, message: text, date: Date())
    )

    let (_, response) = try await urlSession.data(for: request, delegate: nil)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw "The server responded with an error."
    }
  }

  /// A URL session that goes on indefinitely, receiving live updates.
  private var liveURLSession: URLSession = {
    var configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = .infinity
    return URLSession(configuration: configuration)
  }()
}
