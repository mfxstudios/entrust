//
//  String+GitBranch.swift
//  entrust
//
//  Created by Prince Ugwuh on 11/22/25.
//

import Foundation

extension String {
    /// Sanitize a string to be a valid Git branch name
    ///
    /// Git branch name rules:
    /// - Cannot contain spaces, ~, ^, :, ?, *, [, \, or consecutive dots
    /// - Cannot begin or end with a slash
    /// - Cannot end with .lock
    /// - Cannot contain @{
    /// - Cannot be a single @ character
    ///
    /// This function:
    /// - Replaces spaces with hyphens
    /// - Removes or replaces invalid characters
    /// - Ensures it doesn't start/end with slashes or dots
    /// - Converts to lowercase for consistency
    func sanitizedForBranchName() -> String {
        var sanitized = self
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Replace spaces with hyphens
        sanitized = sanitized.replacingOccurrences(of: " ", with: "-")

        // Replace multiple consecutive hyphens with a single hyphen
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }

        // Remove invalid characters: ~, ^, :, ?, *, [, ], \, @, {, }, (, ), !, #
        let invalidCharacters = CharacterSet(charactersIn: "~^:?*[]\\@{}()!#")
            .union(.controlCharacters)
            .union(.illegalCharacters)

        sanitized = sanitized.components(separatedBy: invalidCharacters).joined(separator: "-")

        // Replace multiple consecutive hyphens again (from joining)
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }

        // Replace consecutive dots with single dot
        while sanitized.contains("..") {
            sanitized = sanitized.replacingOccurrences(of: "..", with: ".")
        }

        // Remove leading/trailing slashes, dots, and hyphens
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "/.-"))

        // If it ends with .lock, remove it
        if sanitized.hasSuffix(".lock") {
            sanitized = String(sanitized.dropLast(5))
        }

        // If empty after sanitization, return a default
        if sanitized.isEmpty {
            return "task"
        }

        // Ensure it's not just "@"
        if sanitized == "@" {
            return "task"
        }

        return sanitized
    }
}
