//
//  LANScannerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран сканера локальной сети: поиск устройств по ответам на TCP-порты (ARP-таблица приложениям iOS недоступна)
public struct LANScannerView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var devices: [LANDevice] = []
    @State private var isScanning: Bool = false
    @State private var scanProgress: Double = 0.0
    @State private var scannedHostCount: Int = 0
    @State private var selectedDevice: LANDevice?
    @State private var totalHostCount: Int = 0
    @State private var subnet: LANSubnet?
    @State private var scanTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var accessDenied: Bool = false
    @State private var hasCompletedScan: Bool = false

    private var securityRiskCount: Int {
        devices.flatMap { $0.openPorts }.filter { $0.isCriticalSecurityRisk }.count
    }

    public var body: some View {
        ZStack {
            NPTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 1. Сводная карточка подсети и статус безопасности
                    subnetSummaryHeroCard

                    // 3. Индикатор прогресса сканирования подсети
                    if isScanning {
                        scanProgressCard
                    }

                    if let errorMessage {
                        scanErrorCard(message: errorMessage)
                    }

                    // 3. Список обнаруженных устройств
                    devicesListSection

                    // 4. Пояснение безопасности домашней сети
                    securityNoticeCard
                }
                .padding(.vertical)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("LAN Сканер")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            // Сканирование создаёт десятки соединений — при уходе с экрана оно останавливается
            scanTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startScan()
                } label: {
                    if isScanning {
                        ProgressView()
                            .tint(NPTheme.accentPrimary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }
                }
                .disabled(isScanning)
                .npMinHitTarget()
            }
        }
        .sheet(item: $selectedDevice) { dev in
            LANDeviceDetailSheet(device: dev)
        }
        .task {
            if devices.isEmpty {
                startScan()
            }
        }
    }

    // MARK: - 1. Сводная карточка подсети

    private var subnetSummaryHeroCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(NPTheme.accentPrimary.opacity(0.12))
                        .frame(width: 50, height: 50)

                    Image(systemName: "wifi.router.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(NPTheme.accentPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Устройства в вашей сети")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)

                    Text("Подсеть: \(subnet?.cidrDescription ?? viewModel.systemInfo.localIP)")
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(NPTheme.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(devices.count)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(NPTheme.accentPrimary)

                    Text("найдено")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NPTheme.textTertiary)
                }
            }

            Divider()
                .background(NPTheme.border)

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: securityRiskCount > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(securityRiskCount > 0 ? NPTheme.semanticWarn : NPTheme.accentPrimary)

                    Text(securityRiskCount > 0
                         ? "Служб, которые стоит проверить: \(securityRiskCount)"
                         : (hasCompletedScan ? "Среди проверенных портов таких служб нет" : "Сканирование не выполнялось"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NPTheme.textPrimary)
                }

                Spacer()

                Button {
                    startScan()
                } label: {
                    Text("Сканировать")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(NPTheme.backgroundDeep)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(NPTheme.accentPrimary)
                        .clipShape(Capsule())
                }
                .disabled(isScanning)
                .buttonStyle(NPPressableButtonStyle(scale: 0.94))
            }
        }
        .padding(16)
        .npGlassCard(cornerRadius: 18)
        .padding(.horizontal)
    }

    // MARK: - 2. Индикатор прогресса

    private var scanProgressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Сканирование IP-адресов...")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)

                Spacer()

                Text("\(scannedHostCount)/\(totalHostCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(NPTheme.textSecondary)
            }

            ProgressView(value: scanProgress)
                .tint(NPTheme.accentPrimary)
        }
        .padding(14)
        .npGlassCard(cornerRadius: 14)
        .padding(.horizontal)
    }

    // MARK: - 3. Список устройств

    private var devicesListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("НАЙДЕННЫЕ УЗЛЫ (\(devices.count)):")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NPTheme.textTertiary)
                .tracking(0.5)
                .padding(.horizontal)

            if devices.isEmpty && !isScanning {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 32))
                        .foregroundStyle(NPTheme.textTertiary)
                    Text(hasCompletedScan
                         ? "Устройства не найдены. Проверьте, что NetPulse разрешён доступ к локальной сети (Настройки iOS → Конфиденциальность → Локальная сеть)."
                         : "Нажмите «Сканировать», чтобы найти устройства в вашей Wi-Fi сети")
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .npGlassCard(cornerRadius: 16)
                .padding(.horizontal)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(devices) { device in
                        deviceRow(device)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func deviceRow(_ device: LANDevice) -> some View {
        Button {
            selectedDevice = device
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(device.isCurrentDevice ? NPTheme.accentPrimary.opacity(0.18) : Color.white.opacity(0.06))
                        .frame(width: 40, height: 40)

                    Image(systemName: device.deviceType.systemIcon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(device.isCurrentDevice ? NPTheme.accentPrimary : NPTheme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(NPTheme.textPrimary)

                        if device.isCurrentDevice {
                            Text("ЭТО УСТРОЙСТВО")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(NPTheme.backgroundDeep)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(NPTheme.accentPrimary)
                                .clipShape(Capsule())
                        } else if device.isGateway {
                            Text("РОУТЕР")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(NPTheme.textPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.3))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Text(device.ipAddress)
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(NPTheme.textSecondary)

                        if let vendor = device.vendorName {
                            Text("• \(vendor)")
                                .font(.system(size: 11))
                                .foregroundStyle(NPTheme.textTertiary)
                        } else if let hint = device.serviceHint {
                            Text("• \(hint)")
                                .font(.system(size: 11))
                                .foregroundStyle(NPTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let ping = device.responseTimeMs {
                        Text(String(format: "%.1f мс", ping))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(ping < 20 ? NPTheme.accentPrimary : NPTheme.semanticWarn)
                    }

                    if !device.openPorts.isEmpty {
                        Text("\(device.openPorts.count) порт(ов)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(device.openPorts.contains(where: { $0.isCriticalSecurityRisk }) ? NPTheme.semanticWarn : NPTheme.textTertiary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NPTheme.textTertiary)
            }
            .padding(12)
            .npGlassCard(cornerRadius: 14)
        }
        .buttonStyle(NPPressableButtonStyle(scale: 0.98))
    }

    // MARK: - 4. Безопасность домашней сети

    private var securityNoticeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                    .foregroundStyle(NPTheme.accentPrimary)
                Text("Аудит безопасности локальной сети")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
            }

            Text("Сканер находит устройства, которые открыли один из 9 проверяемых TCP-портов или ответили отказом в соединении, и отмечает службы, на которые стоит обратить внимание (SSH, общие папки SMB, видеопоток RTSP). Это не полноценный аудит безопасности.")
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textSecondary)

            Text("Ограничение: устройства, которые молча отбрасывают такие соединения (многие смартфоны, умные колонки, часть IoT), в списке не появятся. Полный список подключённых устройств есть в панели управления роутера.")
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textTertiary)

            if subnet?.isTruncated == true {
                Text("Сеть шире /24: проверен только блок /24, в котором находится это устройство.")
                    .font(.system(size: 11))
                    .foregroundStyle(NPTheme.semanticWarn)
            }
        }
        .padding(14)
        .npGlassCard(cornerRadius: 14)
        .padding(.horizontal)
    }

    // MARK: - Ошибки

    private func scanErrorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(NPTheme.semanticWarn)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
                    .multilineTextAlignment(.leading)
            }

            if accessDenied {
                Button("Открыть Настройки iOS") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NPTheme.accentPrimary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .npGlassCard(cornerRadius: 14)
        .padding(.horizontal)
    }

    // MARK: - Запуск сканирования

    private func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0.0
        scannedHostCount = 0
        totalHostCount = 0
        devices = []
        errorMessage = nil
        accessDenied = false
        HapticManager.shared.impactMedium()

        let localIP = viewModel.systemInfo.localIP
        let gatewayIP = viewModel.systemInfo.gatewayIP
        let connectionType = viewModel.systemInfo.connectionType

        scanTask = Task {
            let result = await LANScannerEngine.shared.scanSubnet(
                localIP: localIP,
                gatewayIP: gatewayIP,
                connectionType: connectionType
            ) { current, total, newDevice in
                Task { @MainActor in
                    self.scannedHostCount = current
                    self.totalHostCount = total
                    self.scanProgress = total > 0 ? Double(current) / Double(total) : 0.0
                    if let dev = newDevice, !self.devices.contains(where: { $0.ipAddress == dev.ipAddress }) {
                        self.devices.append(dev)
                    }
                }
            }

            switch result {
            case .success(let report):
                self.devices = report.devices
                self.subnet = report.subnet
                self.totalHostCount = report.scannedHostCount
                self.hasCompletedScan = true
                HapticManager.shared.notificationSuccess()
            case .failure(let error):
                if error != .cancelled {
                    self.errorMessage = error.localizedDescription
                    self.accessDenied = (error == .localNetworkAccessDenied)
                    HapticManager.shared.notificationWarning()
                }
            }
            self.isScanning = false
            self.scanTask = nil
        }
    }
}

/// Модальный экран детальной информации об устройстве
private struct LANDeviceDetailSheet: View {
    let device: LANDevice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Карточка устройства
                        VStack(spacing: 10) {
                            Image(systemName: device.deviceType.systemIcon)
                                .font(.system(size: 40))
                                .foregroundStyle(NPTheme.accentPrimary)

                            Text(device.displayName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(NPTheme.textPrimary)

                            Text(device.ipAddress)
                                .font(.system(size: 14, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(NPTheme.textSecondary)

                            if let hint = device.serviceHint {
                                Text(hint)
                                    .font(.system(size: 12))
                                    .foregroundStyle(NPTheme.textTertiary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .npGlassCard(cornerRadius: 18)

                        // Открытые порты
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ОТКРЫТЫЕ ПОРТЫ (ИЗ ПРОВЕРЕННЫХ):")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NPTheme.textTertiary)

                            if device.openPorts.isEmpty {
                                Text("Из проверенных портов (22, 53, 80, 443, 445, 554, 7000, 8080, 62078) открытых нет: устройство ответило отказом в соединении.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(NPTheme.textSecondary)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .npGlassCard(cornerRadius: 12)
                            } else {
                                ForEach(device.openPorts) { port in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Порт \(port.port) — \(port.serviceName)")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(NPTheme.textPrimary)

                                            Text(port.serviceDescription)
                                                .font(.system(size: 11))
                                                .foregroundStyle(NPTheme.textSecondary)
                                        }

                                        Spacer()

                                        if port.isCriticalSecurityRisk {
                                            Text("ПРОВЕРИТЬ")
                                                .font(.system(size: 9, weight: .black))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.red)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .padding(12)
                                    .npGlassCard(cornerRadius: 12)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Параметры устройства")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .foregroundStyle(NPTheme.accentPrimary)
                }
            }
        }
    }
}
