import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case detecting
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var isEnabled: Bool {
        self == .enabled
    }
}

@MainActor
final class LaunchAtLoginService {
    func status() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .disabled
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ isEnabled: Bool) throws -> LaunchAtLoginStatus {
        if isEnabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }

        return status()
    }
}
