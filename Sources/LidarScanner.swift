import ARKit
import RealityKit
import Combine

class LidarScanner: NSObject, ObservableObject, ARSessionDelegate {

    @Published var pointCount = 0
    @Published var statusText = "Наведите камеру на объект"
    @Published var isScanning = false
    @Published var isSending = false
    @Published var showSuccess = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var serverIP: String {
        didSet { UserDefaults.standard.set(serverIP, forKey: "serverIP") }
    }

    var arView: ARView?
    private var points: [(x: Float, y: Float, z: Float, r: UInt8, g: UInt8, b: UInt8)] = []
    private var frameCounter = 0
    private let captureEveryNFrames = 8
    private let maxPoints = 800_000

    override init() {
        self.serverIP = UserDefaults.standard.string(forKey: "serverIP") ?? "192.168.1.20"
        super.init()
    }

    // MARK: - Управление сканированием

    func startScanning() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            statusText = "Этот iPhone не поддерживает LiDAR"
            return
        }
        isScanning = true
        statusText = "Сканирование… двигайтесь медленно"
    }

    func stopScanning() {
        isScanning = false
        statusText = "Захвачено \(pointCount.formatted()) точек"
    }

    func clearPoints() {
        points.removeAll()
        pointCount = 0
        statusText = "Наведите камеру на объект"
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isScanning else { return }

        frameCounter += 1
        guard frameCounter % captureEveryNFrames == 0 else { return }
        guard points.count < maxPoints else {
            DispatchQueue.main.async {
                self.statusText = "Максимум достигнут (\(self.maxPoints.formatted()) точек)"
                self.isScanning = false
            }
            return
        }

        processFrame(frame)
    }

    // MARK: - Обработка кадра

    private func processFrame(_ frame: ARFrame) {
        guard let depthMap = frame.smoothedSceneDepth?.depthMap
                          ?? frame.sceneDepth?.depthMap else { return }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let dw = CVPixelBufferGetWidth(depthMap)
        let dh = CVPixelBufferGetHeight(depthMap)
        guard let depthPtr = CVPixelBufferGetBaseAddress(depthMap)?
            .assumingMemoryBound(to: Float32.self) else { return }

        // Цвет из RGB камеры
        let rgbColors = extractColors(from: frame.capturedImage, targetW: dw, targetH: dh)

        // Матрица камеры
        let intr = frame.camera.intrinsics  // column-major simd_float3x3
        let fx = intr[0][0]
        let fy = intr[1][1]
        let cx = intr[2][0]
        let cy = intr[2][1]

        // Мировая трансформация
        let camTransform = frame.camera.transform

        let step = 4
        var newPoints: [(x: Float, y: Float, z: Float, r: UInt8, g: UInt8, b: UInt8)] = []

        for row in stride(from: 0, to: dh, by: step) {
            for col in stride(from: 0, to: dw, by: step) {
                let depth = depthPtr[row * dw + col]
                guard depth > 0.1 && depth < 8.0 else { continue }

                // Локальные координаты в системе камеры
                let xLocal = (Float(col) - cx) * depth / fx
                let yLocal = (Float(row) - cy) * depth / fy
                let zLocal = depth

                // Переводим в мировые координаты
                let localPt = simd_float4(xLocal, -yLocal, -zLocal, 1)
                let worldPt = camTransform * localPt

                // Цвет
                let pixIdx = (row * dw + col) * 3
                let r: UInt8 = pixIdx + 2 < rgbColors.count ? rgbColors[pixIdx]     : 180
                let g: UInt8 = pixIdx + 2 < rgbColors.count ? rgbColors[pixIdx + 1] : 180
                let b: UInt8 = pixIdx + 2 < rgbColors.count ? rgbColors[pixIdx + 2] : 180

                newPoints.append((x: worldPt.x, y: worldPt.y, z: worldPt.z, r: r, g: g, b: b))
            }
        }

        points.append(contentsOf: newPoints)

        let total = points.count
        DispatchQueue.main.async {
            self.pointCount = total
        }
    }

    private func extractColors(from pixelBuffer: CVPixelBuffer, targetW: Int, targetH: Int) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let srcW = CVPixelBufferGetWidth(pixelBuffer)
        let srcH = CVPixelBufferGetHeight(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        var colors = [UInt8](repeating: 180, count: targetW * targetH * 3)

        for row in 0..<targetH {
            for col in 0..<targetW {
                let srcRow = row * srcH / targetH
                let srcCol = col * srcW / targetW
                let srcIdx = srcRow * bytesPerRow + srcCol * 4

                let outIdx = (row * targetW + col) * 3
                colors[outIdx]     = ptr[srcIdx + 2] // R
                colors[outIdx + 1] = ptr[srcIdx + 1] // G
                colors[outIdx + 2] = ptr[srcIdx]     // B
            }
        }
        return colors
    }

    // MARK: - PLY экспорт

    func buildPLY() -> Data {
        var header = "ply\n"
        header += "format binary_little_endian 1.0\n"
        header += "element vertex \(points.count)\n"
        header += "property float x\n"
        header += "property float y\n"
        header += "property float z\n"
        header += "property uchar red\n"
        header += "property uchar green\n"
        header += "property uchar blue\n"
        header += "end_header\n"

        var data = header.data(using: .utf8)!
        data.reserveCapacity(data.count + points.count * 15)

        for pt in points {
            var x = pt.x, y = pt.y, z = pt.z
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { data.append(contentsOf: $0) }
            data.append(contentsOf: [pt.r, pt.g, pt.b])
        }
        return data
    }

    // MARK: - Отправка на ПК

    func sendToPC() {
        isSending = true
        statusText = "Отправка \(pointCount.formatted()) точек…"

        let plyData = buildPLY()
        let urlString = "http://\(serverIP):8765/upload-scan"

        guard let url = URL(string: urlString) else {
            showErr("Неверный IP: \(serverIP)")
            return
        }

        let boundary = "BIMScanner-\(UUID().uuidString)"
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body += "--\(boundary)\r\n".utf8data
        body += "Content-Disposition: form-data; name=\"file\"; filename=\"lidar_scan.ply\"\r\n".utf8data
        body += "Content-Type: application/octet-stream\r\n\r\n".utf8data
        body += plyData
        body += "\r\n--\(boundary)--\r\n".utf8data

        URLSession.shared.uploadTask(with: request, from: body) { [weak self] _, response, error in
            DispatchQueue.main.async {
                self?.isSending = false
                if let error = error {
                    self?.showErr("Ошибка сети: \(error.localizedDescription)\nПроверьте IP и Wi-Fi")
                } else {
                    self?.showSuccess = true
                    self?.points.removeAll()
                    self?.pointCount = 0
                    self?.statusText = "Наведите камеру на объект"
                }
            }
        }.resume()
    }

    private func showErr(_ msg: String) {
        isSending = false
        errorMessage = msg
        showError = true
    }
}

private extension String {
    var utf8data: Data { Data(utf8) }
}
private extension Data {
    static func += (lhs: inout Data, rhs: Data) { lhs.append(rhs) }
    static func += (lhs: inout Data, rhs: String.UTF8View) { lhs.append(contentsOf: rhs) }
}
