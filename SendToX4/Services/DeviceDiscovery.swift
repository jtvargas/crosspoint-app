import Foundation
import Network

/// Result of device discovery.
enum DiscoveryResult: Sendable {
    case stock(StockFirmwareService)
    case crossPoint(CrossPointFirmwareService)
    case custom(any DeviceService)
    case notFound
    
    var service: (any DeviceService)? {
        switch self {
        case .stock(let s): return s
        case .crossPoint(let s): return s
        case .custom(let s): return s
        case .notFound: return nil
        }
    }
    
    var firmwareLabel: String {
        switch self {
        case .stock: return "Stock"
        case .crossPoint: return "CrossPoint"
        case .custom: return "Custom"
        case .notFound: return "Not Connected"
        }
    }
}

/// Discovers the X4 device by probing known firmware endpoints.
enum DeviceDiscovery {
    
    /// Auto-detect the X4 device by trying Stock and CrossPoint endpoints concurrently.
    /// CrossPoint detection tries crosspoint.local first, then falls back to static IP.
    static func detect() async -> DiscoveryResult {
        // Probe stock and CrossPoint in parallel
        async let stockResult = probeStock()
        async let crossPointResult = probeCrossPoint()
        
        let stock = await stockResult
        let crossPoint = await crossPointResult
        
        // Prefer CrossPoint via .local if found, then CrossPoint IP, then Stock
        if let cpService = crossPoint {
            return .crossPoint(cpService)
        }
        if stock {
            return .stock(StockFirmwareService())
        }
        
        return .notFound
    }
    
    /// Detect with a specific firmware type and optional custom IP.
    static func detect(firmwareType: FirmwareType, customIP: String) async -> DiscoveryResult {
        switch firmwareType {
        case .stock:
            let service = StockFirmwareService()
            return await service.checkReachability() ? .stock(service) : .notFound
            
        case .crossPoint:
            // Try crosspoint.local first, then fall back to static IP
            if let service = await probeCrossPoint() {
                return .crossPoint(service)
            }
            return .notFound
            
        case .custom:
            let host = customIP.isEmpty ? "192.168.3.3" : customIP
            // Try stock API first on custom host
            let stockService = StockFirmwareService(ip: host)
            if await stockService.checkReachability() {
                return .stock(stockService)
            }
            // Try CrossPoint API on custom host
            let cpService = CrossPointFirmwareService(host: host)
            if await cpService.checkReachability() {
                return .crossPoint(cpService)
            }
            return .notFound
        }
    }
    
    // MARK: - Private Probes
    
    private static func probeStock() async -> Bool {
        await StockFirmwareService().checkReachability()
    }
    
    /// Probe CrossPoint: try crosspoint.local first, fall back to static IP.
    /// Returns the working service instance, or nil if neither is reachable.
    private static func probeCrossPoint() async -> CrossPointFirmwareService? {
        // Priority 1: mDNS hostname
        let localService = CrossPointFirmwareService(host: CrossPointFirmwareService.localHostname)
        if await localService.checkReachability() {
            return localService
        }
        
        // Priority 2: static IP fallback
        let ipService = CrossPointFirmwareService(host: CrossPointFirmwareService.defaultIP)
        if await ipService.checkReachability() {
            return ipService
        }
        
        return nil
    }
}
