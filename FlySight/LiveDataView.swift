//
//  LiveDataVie.swift
//  FlySight
//
//  Created by Michael Cooper on 2025-05-19.
//

import SwiftUI
import FlySightCore

struct LiveDataView: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager

    // Local state for toggles, initialized by bluetoothManager.currentGNSSMask
    @State private var enableTimeOfWeek: Bool = true
    // @State private var enableWeekNumber: Bool = false // Not currently supported by firmware PV packet
    @State private var enablePosition: Bool = true
    @State private var enableVelocity: Bool = true
    @State private var enableAccuracy: Bool = false
    @State private var enableNumSV: Bool = false

    var body: some View {
        NavigationView {
            if case .connected = bluetoothManager.connectionState {
                Form {
                    Section(header: Text("Live Data Stream")) {
                        if let data = bluetoothManager.liveGNSSData {
                            Text("Reported Mask: \(String(format: "0x%02X", data.mask))")
                                .font(.caption)
                                .foregroundColor(.gray)

                            if data.timeOfWeek != nil { Text("Time of Week: \(data.timeOfWeek!) ms") }
                            if data.latitude != nil { Text("Latitude: \(data.formattedLatitude)") }
                            if data.longitude != nil { Text("Longitude: \(data.formattedLongitude)") }
                            if data.heightMSL != nil { Text("Height MSL: \(data.formattedHeightMSL)") }
                            if data.velocityNorth != nil { Text("Velocity N: \(data.formattedVelocityNorth)") }
                            if data.velocityEast != nil { Text("Velocity E: \(data.formattedVelocityEast)") }
                            if data.velocityDown != nil { Text("Velocity D: \(data.formattedVelocityDown)") }
                            if data.horizontalAccuracy != nil { Text("Horizontal Acc.: \(data.formattedHorizontalAccuracy)") }
                            if data.verticalAccuracy != nil { Text("Vertical Acc.: \(data.formattedVerticalAccuracy)") }
                            if data.speedAccuracy != nil { Text("Speed Acc.: \(data.formattedSpeedAccuracy)") }
                            if data.numSV != nil { Text("Satellites in Solution: \(data.numSV!)") }
                        } else {
                            Text("No live data packets received yet.")
                                .foregroundColor(.gray)
                                .padding(.vertical)
                        }
                    }

                    Section(header: Text("Configure Data Fields (Current Effective Mask: \(String(format: "0x%02X", bluetoothManager.currentGNSSMask)))")) {
                        Toggle("Time of Week", isOn: $enableTimeOfWeek)
                            .onChange(of: enableTimeOfWeek) { _ in applyMaskConfigurationFromToggles() }
                        Toggle("Position (Lat, Lon, Alt)", isOn: $enablePosition)
                            .onChange(of: enablePosition) { _ in applyMaskConfigurationFromToggles() }
                        Toggle("Velocity (N, E, D)", isOn: $enableVelocity)
                            .onChange(of: enableVelocity) { _ in applyMaskConfigurationFromToggles() }
                        Toggle("Accuracy (H, V, S)", isOn: $enableAccuracy)
                            .onChange(of: enableAccuracy) { _ in applyMaskConfigurationFromToggles() }
                        Toggle("Number of Satellites", isOn: $enableNumSV)
                            .onChange(of: enableNumSV) { _ in applyMaskConfigurationFromToggles() }

                        // Status of mask update
                        switch bluetoothManager.gnssMaskUpdateStatus {
                        case .idle:
                            EmptyView() // Or Text("Ready to update mask.").font(.caption).foregroundColor(.gray)
                        case .pending:
                            HStack {
                                Spacer()
                                ProgressView().scaleEffect(0.7)
                                Text("Applying mask...")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                        case .failure(let message):
                            HStack {
                                Spacer()
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                                Text("Mask update failed: \(message)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                Spacer()
                            }
                            .onAppear { // Auto-clear failure message after a delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                    if case .failure = bluetoothManager.gnssMaskUpdateStatus {
                                        bluetoothManager.gnssMaskUpdateStatus = .idle
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Live GNSS Data")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            bluetoothManager.fetchGNSSMask()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(bluetoothManager.gnssMaskUpdateStatus == .pending)
                    }
                }
                .onAppear {
                    // Fetch initial mask when view appears if connected
                    if case .connected = bluetoothManager.connectionState {
                        if bluetoothManager.gnssMaskUpdateStatus != .pending {
                            bluetoothManager.fetchGNSSMask() // This will also update toggles via onReceive
                        }
                    }
                    // Update toggles from the manager's currentGNSSMask if not already mid-update
                    if bluetoothManager.gnssMaskUpdateStatus != .pending {
                         updateToggleStates(from: bluetoothManager.currentGNSSMask)
                    }
                }
                .onReceive(bluetoothManager.$currentGNSSMask) { newMaskFromManager in
                    // Only update toggles if the source of truth (manager) changes and we are not pending an update.
                    // This prevents cycles if a toggle change updates the manager which then updates toggles.
                    if bluetoothManager.gnssMaskUpdateStatus != .pending {
                        updateToggleStates(from: newMaskFromManager)
                    }
                }
            } else { // Not connected
                VStack {
                    Spacer()
                    Image(systemName: "waveform.path.ecg.badge.xmark")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                        .padding(.bottom)
                    Text("Not Connected")
                        .font(.headline)
                    Text("Connect to a FlySight to view live data and configure data fields.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .navigationTitle("Live GNSS Data")
            }
        }
    }

    private func updateToggleStates(from mask: UInt8) {
        // This function synchronizes the @State toggles with the mask from BluetoothManager.
        // It's called on .onAppear and when bluetoothManager.$currentGNSSMask changes.
        let newEnableTimeOfWeek = (mask & FlySightCore.GNSSLiveMaskBits.timeOfWeek) != 0
        let newEnablePosition = (mask & FlySightCore.GNSSLiveMaskBits.position) != 0
        let newEnableVelocity = (mask & FlySightCore.GNSSLiveMaskBits.velocity) != 0
        let newEnableAccuracy = (mask & FlySightCore.GNSSLiveMaskBits.accuracy) != 0
        let newEnableNumSV = (mask & FlySightCore.GNSSLiveMaskBits.numSV) != 0

        if enableTimeOfWeek != newEnableTimeOfWeek { enableTimeOfWeek = newEnableTimeOfWeek }
        if enablePosition != newEnablePosition { enablePosition = newEnablePosition }
        if enableVelocity != newEnableVelocity { enableVelocity = newEnableVelocity }
        if enableAccuracy != newEnableAccuracy { enableAccuracy = newEnableAccuracy }
        if enableNumSV != newEnableNumSV { enableNumSV = newEnableNumSV }
    }

    private func applyMaskConfigurationFromToggles() {
        guard bluetoothManager.gnssMaskUpdateStatus != .pending else { return } // Don't send if an update is already pending

        var newMask: UInt8 = 0
        if enableTimeOfWeek { newMask |= FlySightCore.GNSSLiveMaskBits.timeOfWeek }
        if enablePosition { newMask |= FlySightCore.GNSSLiveMaskBits.position }
        if enableVelocity { newMask |= FlySightCore.GNSSLiveMaskBits.velocity }
        if enableAccuracy { newMask |= FlySightCore.GNSSLiveMaskBits.accuracy }
        if enableNumSV { newMask |= FlySightCore.GNSSLiveMaskBits.numSV }

        // Only send update if the new mask is different from what the manager currently believes the mask is.
        // This prevents re-sending the same mask if toggles are just reflecting the current state.
        if newMask != bluetoothManager.currentGNSSMask {
            bluetoothManager.updateGNSSMask(newMask: newMask)
        }
    }
}

struct LiveDataView_Previews: PreviewProvider {
    static var previews: some View {
        let mockBm = FlySightCore.BluetoothManager()
        // mockBm.connectionState = .connected(to: ...)
        // mockBm.liveGNSSData = FlySightCore.LiveGNSSData(...)
        LiveDataView(bluetoothManager: mockBm)
    }
}
