import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = LidarScanner()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            ARViewContainer(scanner: scanner)
                .ignoresSafeArea()

            VStack {
                // Верхняя панель
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BIM LiDAR Scanner")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(scanner.statusText)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(.black.opacity(0.5))

                Spacer()

                // Счётчик точек
                if scanner.pointCount > 0 {
                    Text("\(scanner.pointCount.formatted()) точек")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                }

                Spacer()

                // Кнопки
                VStack(spacing: 12) {
                    if scanner.isSending {
                        ProgressView("Отправка на ПК…")
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .foregroundColor(.white)
                    } else {
                        if scanner.pointCount > 0 {
                            Button {
                                scanner.sendToPC()
                            } label: {
                                Label("Отправить на ПК", systemImage: "arrow.up.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                            }

                            Button {
                                scanner.clearPoints()
                            } label: {
                                Label("Очистить", systemImage: "trash")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }

                        Button {
                            scanner.isScanning ? scanner.stopScanning() : scanner.startScanning()
                        } label: {
                            Label(
                                scanner.isScanning ? "Остановить" : "Начать сканирование",
                                systemImage: scanner.isScanning ? "stop.circle.fill" : "camera.fill"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(scanner.isScanning ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(serverIP: $scanner.serverIP)
        }
        .alert("Готово!", isPresented: $scanner.showSuccess) {
            Button("OK") {}
        } message: {
            Text("Скан отправлен на ПК.\nОткройте BIM Scanner и конвертируйте в DXF/OBJ.")
        }
        .alert("Ошибка", isPresented: $scanner.showError) {
            Button("OK") {}
        } message: {
            Text(scanner.errorMessage)
        }
    }
}
