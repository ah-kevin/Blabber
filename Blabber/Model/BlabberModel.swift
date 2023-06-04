import Combine
import CoreLocation
import Foundation
import UIKit

/// The app model that communicates with the server.
@MainActor
class BlabberModel: ObservableObject {
  var username = ""
  var urlSession = URLSession.shared

  nonisolated init() {}
  private let manager = CLLocationManager()
  private var delegate: ChatLocationDelegate?

  /// Current live updates
  @Published var messages: [Message] = []

  /// Shares the current user's address in chat.
  func shareLocation() async throws {
    let location: CLLocation = try await withCheckedThrowingContinuation { [weak self] continuation in
      self?.delegate = ChatLocationDelegate(manager: manager, continuation: continuation)
      if manager.authorizationStatus == .authorizedWhenInUse {
        manager.startUpdatingLocation()
      }
    }
    print(location.description)
    manager.stopUpdatingLocation()
    delegate = nil
    let address: String = try await withCheckedThrowingContinuation { continuation in
      AddressEncoder.addressFor(location: location) { address, error in
        switch (address, error) {
        case (nil, let error?):
          continuation.resume(throwing: error)
        case (let address?, nil):
          continuation.resume(returning: address)
        case (nil, nil):
          continuation.resume(throwing: "Address encoding failed")
        case let (address?, error?):
          continuation.resume(returning: address)
          print(error)
        }
      }
    }
    try await say("📍 \(address)")
  }

  /// Does a countdown and sends the message.
  func countdown(to message: String) async throws {
    guard !message.isEmpty else { return }
    var countdown = 3
    let counter = AsyncStream<String> {
      guard countdown >= 0 else { return nil }
      do {
        try await Task.sleep(for: .seconds(1))
      } catch {
        return nil
      }
      defer { countdown -= 1 }
      if countdown == 0 {
        return "🎉 " + message
      } else {
        return "\(countdown)..."
      }
    }
//    for await countdownMessage in counter {
//      try await say(countdownMessage)
//    }
    try await counter.forEach {
      try await say($0)
    }
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
    var iterator = stream.lines.makeAsyncIterator()
    guard let first = try await iterator.next() else {
      throw "No response from server"
    }
    guard let data = first.data(using: .utf8), let status = try? JSONDecoder().decode(ServerStatus.self, from: data)
    else {
      throw "Invalid response from server"
    }
    messages.append(Message(message: "\(status.activeUsers) active users"))
    let notifications = Task {
      await observeAppStatus()
    }
    defer {
      notifications.cancel()
    }
    for try await line in stream.lines {
      if let data = line.data(using: .utf8), let update = try? JSONDecoder().decode(Message.self, from: data) {
        messages.append(update)
      }
    }
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

  func observeAppStatus() async {
    Task {
      for await _ in NotificationCenter.default.notifications(for: UIApplication.willResignActiveNotification)
      {
        try? await say("\(username) went away", isSystemMessage: true)
      }
    }
    Task {
      for await _ in NotificationCenter.default.notifications(for: UIApplication.didBecomeActiveNotification)
      {
        try? await say("\(username) came back", isSystemMessage: true)
      }
    }
  }
}

extension AsyncSequence {
  func forEach(_ body: (Element) async throws -> Void) async throws {
    for try await element in self {
      try await body(element)
    }
  }
}
