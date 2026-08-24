//
//  LANScannerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран сканера локальной сети и аудита безопасности Wi-Fi
public struct LANScannerView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var isScanning: Bool = false
    @State private var scannedProgress: Int = 0
    @State private var totalHosts: Int = 254
    @State private var devices: [LANDevice] = []
    @State private var selectedDevice: LANDevice?

    private var securityRiskCount: Int {
        devices.flatMap { $0.openPorts }.filter { $0.isCriticalSecurityRisk }.count
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Сводная карточка подсети и статус безопасности
                        subnetSummaryHeroCard

                        // 2. Индикатор прогресса сканирования подсети
                        if isScanning {
                            scanProgressCard
                        }

                        // 3. Список обнаруженных устройств
                        devicesListSection

                        // 4. Пояснение безопасности домашней сети
                        securityNoticeCard
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("LAN Сканер")
            .navigationBarTitleDisplayMode(.inline)
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

                    Text("Подсеть: \(viewModel.systemInfo.localIP)/24")
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

                    Text("в сети")
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

                    Text(securityRiskCount > 0 ? "Обнаружены открытые порты (\(securityRiskCount))" : "Критических рисков не выявлено")
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
            }
        }
        .padding(16)
        .npGlassCard(cornerRadius: 20)
        .padding(.horizontal)
    }

    // MARK: - 2. Индикатор прогресса

    private var scanProgressCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Сканирование адресов 1...\(totalHosts)...")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NPTheme.textSecondary)
                Spacer()
                Text("\(scannedProgress)/\(totalHosts)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(NPTheme.accentPrimary)
            }

            ProgressView(value: Double(scannedProgress), total: Double(totalHosts))
                .tint(NPTheme.accentPrimary)
        }
        .padding(14)
        .npGlassCard(cornerRadius: 14)
        .padding(.horizontal)
    }

    // MARK: - 3. Список обнаруженных устройств

    private var devicesListSection: some View {
        VStack(spacing: 10) {
            ForEach(devices) { device in
                Button {
                    selectedDevice = device
                    HapticManager.shared.impactLight()
                } label: {
                    deviceRow(device: device)
                }
                .buttonStyle(NPPressableButtonStyle())
            }
        }
        .padding(.horizontal)
    }

    private func deviceRow(device: LANDevice) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(device.isGateway ? NPTheme.accentPrimary.opacity(0.15) : Color.white.opacity(0.06))
                    .frame(width: 42, height: 42)

                Image(systemName: device.deviceType.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(device.isGateway ? NPTheme.accentPrimary : NPTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)
                        .lineLimit(1)

                    if device.isGateway {
                        Text("ROUTER")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(NPTheme.accentPrimary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(NPTheme.accentPrimary.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if device.isCurrentDevice {
                        Text("THIS IPHONE")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(NPTheme.accentSilver)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Text(device.ipAddress)
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(NPTheme.textSecondary)

                    if !device.openPorts.isEmpty {
                        Text("• \(device.openPorts.count) порт(ов)")
                            .font(.system(size: 10))
                            .foregroundStyle(NPTheme.textTertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f мс", device.latencyMs))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NPTheme.accentPrimary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NPTheme.textTertiary)
            }
        }
        .padding(12)
        .npGlassCard(cornerRadius: 14)
    }

    // MARK: - 4. Карточка безопасности

    private var securityNoticeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(NPTheme.accentPrimary)
                Text("Аудит безопасности домашнего Wi-Fi")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
            }

            Text("Если вы видите неизвестные IP-адреса в списке — возможно, к вашему Wi-Fi подключены соседи или незащищенные IoT-гаджеты. Рекомендуется сменить пароль сети на WPA3 и отключить WPS.")
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textSecondary)
        }
        .padding(14)
        .npGlassCard(cornerRadius: 14)
        .padding(.horizontal)
    }

    // MARK: - Сканирование

    private func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scannedProgress = 0
        devices = []
        HapticManager.shared.impactMedium()

        Task {
            let res = await LANScannerEngine.shared.scanSubnet(
                localIP: viewModel.systemInfo.localIP,
                gatewayIP: viewModel.systemInfo.gatewayIP
            ) { scanned, total, dev in
                Task { @MainActor in
                    self.scannedProgress = scanned
                    self.totalHosts = total
                    if let dev = dev, !devices.contains(where: { $0.id == dev.id }) {
                        self.devices.append(dev)
                    }
                }
            }

            self.devices = res
            self.isScanning = false
            HapticManager.shared.notificationSuccess()
        }
    }
}

// MARK: - Детальный лист информации об устройстве

private struct LANDeviceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let device: LANDevice

    var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Верхняя карточка устройства
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(NPTheme.accentPrimary.opacity(0.12))
                                    .frame(width: 54, height: 54)

                                Image(systemName: device.deviceType.icon)
                                    .font(.system(size: 24))
                                    .foregroundStyle(NPTheme.accentPrimary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.displayName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(NPTheme.textPrimary)

                                Text(device.deviceType.rawValue)
                                    .font(.system(size: 12))
                                    .foregroundStyle(NPTheme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // Таблица сетевых атрибутов
                        VStack(spacing: 8) {
                            attributeRow(title: "IP-Адрес", value: device.ipAddress)
                            if let mac = device.macAddress {
                                attributeRow(title: "MAC-Адрес", value: mac)
                            }
                            if let vendor = device.vendorName {
                                attributeRow(title: "Производитель", value: vendor)
                            }
                            attributeRow(title: "Отклик (RTT)", value: String(format: "%.1f мс", device.latencyMs))
                        }
                        .padding(14)
                        .npGlassCard(cornerRadius: 16)
                        .padding(.horizontal)

                        // Открытые порты
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ОТКРЫТЫЕ ПОРТЫ И СЛУЖБЫ:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NPTheme.textTertiary)
                                .tracking(0.5)

                            if device.openPorts.isEmpty {
                                Text("Открытых TCP-портов не обнаружено (Устройство закрыто файрволом).")
                                    .font(.system(size: 12))
                                    .foregroundStyle(NPTheme.textSecondary)
                                    .padding(12)
                                    .npGlassCard(cornerRadius: 12)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(device.openPorts) { port in
                                        HStack {
                                            Text("Порт \(port.portNumber)")
                                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                                .monospacedDigit()
                                                .foregroundStyle(NPTheme.textPrimary)

                                            Spacer()

                                            Text(port.serviceName)
                                                .font(.system(size: 12))
                                                .foregroundStyle(port.isCriticalSecurityRisk ? NPTheme.semanticWarn : NPTheme.accentPrimary)
                                        }
                                        .padding(10)
                                        .background(Color.white.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                }
                                .padding(12)
                                .npGlassCard(cornerRadius: 14)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Устройство сети")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)
                }
            }
        }
    }

    private func attributeRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(NPTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(NPTheme.textPrimary)
        }
    }
}
