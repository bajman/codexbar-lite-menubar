import Foundation

public enum ProviderTokenSource: String, Sendable {
    case environment
}

public struct ProviderTokenResolution: Sendable {
    public let token: String
    public let source: ProviderTokenSource

    public init(token: String, source: ProviderTokenSource) {
        self.token = token
        self.source = source
    }
}

/// Legacy compatibility shim.
/// Lite mode no longer resolves per-provider API/cookie tokens from config.
public enum ProviderTokenResolver {
    public static func zaiToken(environment _: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        nil
    }

    public static func syntheticToken(environment _: [String: String] = ProcessInfo.processInfo
        .environment) -> String?
    {
        nil
    }

    public static func copilotToken(environment _: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        nil
    }

    public static func minimaxToken(environment _: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        nil
    }

    public static func minimaxCookie(environment _: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        nil
    }

    public static func kimiAuthToken(environment _: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        nil
    }

    public static func kimiK2Token(environment _: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        nil
    }

    public static func warpToken(environment _: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        nil
    }

    public static func openRouterToken(
        environment _: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        nil
    }

    public static func zaiResolution(
        environment _: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        nil
    }

    public static func syntheticResolution(
        environment _: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        nil
    }

    public static func copilotResolution(
        environment _: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        nil
    }

    public static func minimaxTokenResolution(
        environment _: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        nil
    }

    public static func minimaxCookieResolution(
        environment _: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        nil
    }

    public static func kimiAuthResolution(
        environment _: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        nil
    }

    public static func kimiK2Resolution(
        environment _: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        nil
    }

    public static func warpResolution(
        environment _: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        nil
    }

    public static func openRouterResolution(
        environment _: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        nil
    }
}
