//
//  TimeoutTask.swift
//  BlabberTests
//
//  Created by bjke on 2023/6/4.
//

import Foundation
class TimeoutTask<Success> {}

extension TimeoutTask {
  struct TimeoutError: LocalizedError {
    var errorDescription: String? {
      return "The operation timed out."
    }
  }
}
