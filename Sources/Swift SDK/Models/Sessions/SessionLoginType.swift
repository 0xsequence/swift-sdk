public enum SessionLoginType: String, Codable, Sendable {
    case email = "Email"
    case googleAuth = "GoogleAuth"
    case oidc = "Oidc"
}
