import Foundation
import ServiceManagement

enum LaunchAtLoginError: Error, LocalizedError {
    case serviceNotFound
    case requiresApproval
    case operationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .serviceNotFound:
            return "The login item service could not be found. Move Pinny to Applications and try again."
        case .requiresApproval:
            return "Launch at Login needs approval in System Settings > General > Login Items."
        case .operationFailed(let error):
            return error.localizedDescription
        }
    }
}

final class LaunchAtLoginManager {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    var requiresApproval: Bool {
        service.status == .requiresApproval
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func setEnabled(_ enabled: Bool) -> Result<Bool, LaunchAtLoginError> {
        do {
            if enabled {
                switch service.status {
                case .enabled:
                    return .success(true)
                case .notFound:
                    return .failure(.serviceNotFound)
                case .requiresApproval:
                    return .failure(.requiresApproval)
                case .notRegistered:
                    try service.register()
                @unknown default:
                    try service.register()
                }
            } else {
                switch service.status {
                case .notRegistered:
                    return .success(false)
                case .notFound:
                    return .failure(.serviceNotFound)
                case .enabled, .requiresApproval:
                    try service.unregister()
                @unknown default:
                    try service.unregister()
                }
            }
        } catch {
            return .failure(.operationFailed(error))
        }

        if service.status == .requiresApproval {
            return .failure(.requiresApproval)
        }
        return .success(service.status == .enabled)
    }
}
