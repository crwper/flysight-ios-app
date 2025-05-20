//
//  ConnectView.swift
//  FlySight
//
//  Created by Michael Cooper on 2025-05-19.
//

import SwiftUI
import FlySightCore

struct ConnectView: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager
    @State private var isPresentingAddDeviceSheet = false
    @State private var peripheralToForget: FlySightCore.PeripheralInfo?
    // No @State for showForgetAlert, directly use .alert(item: ...)

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Current connection status bar
                connectionStatusBar()
                    .padding(.horizontal)
                    .padding(.bottom, 5)

                List {
                    Section(header: Text("My FlySights")) {
                        if bluetoothManager.knownPeripherals.isEmpty && bluetoothManager.connectionState != .scanningKnown {
                            Text("No known FlySights. Tap '+' to add a new FlySight, or 'Scan Known' to search for nearby remembered devices.")
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .padding(.vertical)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else if bluetoothManager.knownPeripherals.isEmpty && bluetoothManager.connectionState == .scanningKnown {
                             HStack {
                                 Spacer()
                                 ProgressView()
                                 Text("Scanning for known devices...")
                                     .font(.footnote)
                                     .foregroundColor(.gray)
                                     .padding(.leading, 5)
                                 Spacer()
                             }.padding(.vertical)
                        }

                        ForEach(bluetoothManager.knownPeripherals) { peripheralInfo in
                            KnownPeripheralRow(
                                bluetoothManager: bluetoothManager,
                                peripheralInfo: peripheralInfo,
                                onForget: { infoToForget in
                                    self.peripheralToForget = infoToForget // Triggers .alert(item: ...)
                                }
                            )
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("FlySight Connections")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        if bluetoothManager.currentScanMode == .knownDevices || bluetoothManager.connectionState == .scanningKnown {
                            bluetoothManager.stopScanning()
                        } else {
                            bluetoothManager.loadKnownPeripheralsFromUserDefaults() // Refresh list
                            bluetoothManager.startScanningForKnownDevices()
                        }
                    }) {
                        Text(bluetoothManager.currentScanMode == .knownDevices || bluetoothManager.connectionState == .scanningKnown ? "Stop Scan" : "Scan Known")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresentingAddDeviceSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill") // More prominent icon
                            .imageScale(.large)
                    }
                }
            }
            .sheet(isPresented: $isPresentingAddDeviceSheet) {
                AddDeviceView(bluetoothManager: bluetoothManager)
            }
            .alert(item: $peripheralToForget) { peripheralToConfirmForget in // Use .alert(item: ...)
                Alert(
                    title: Text("Forget Device"),
                    message: Text("Are you sure you want to forget \(peripheralToConfirmForget.name)? This will remove it from the app's known list and disconnect if currently connected."),
                    primaryButton: .destructive(Text("Forget")) {
                        bluetoothManager.forgetDevice(peripheralInfo: peripheralToConfirmForget) {
                            // Completion after user dismisses the system unpairing guidance alert.
                        }
                    },
                    secondaryButton: .cancel() {
                        self.peripheralToForget = nil // Clear selection on cancel
                    }
                )
            }
            .onAppear {
                 // If not connected and not already scanning for known, start scanning.
                 if bluetoothManager.connectedPeripheralInfo == nil &&
                    bluetoothManager.currentScanMode == .none && // only if not already scanning
                    bluetoothManager.connectionState == .idle { // and truly idle
                     bluetoothManager.startScanningForKnownDevices()
                 }
            }
            // Dismiss AddDeviceSheet when a connection is successful from the sheet
            .onReceive(bluetoothManager.$connectionState) { state in
                if case .connected = state, isPresentingAddDeviceSheet {
                    // Check if the connected device was from the pairing list
                    if let connectedInfo = bluetoothManager.connectedPeripheralInfo,
                       !bluetoothManager.knownPeripherals.contains(where: { $0.id == connectedInfo.id && $0.isBonded && $0.isConnected }) {
                        // This condition is a bit complex. Simpler: if sheet is up and we connect, close it.
                         isPresentingAddDeviceSheet = false
                    } else if bluetoothManager.connectedPeripheralInfo != nil {
                        // Generic case: if sheet is up and we are now connected to *any* device successfully.
                        isPresentingAddDeviceSheet = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func connectionStatusBar() -> some View {
        Group {
            switch bluetoothManager.connectionState {
            case .connected(let pInfo):
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                        .foregroundColor(.green)
                    Text("Connected to \(pInfo.name)")
                        .font(.footnote)
                    Spacer()
                    if let fw = bluetoothManager.flysightFirmwareVersion {
                        Text("FW: \(fw)").font(.caption).foregroundColor(.gray)
                    }
                }
            case .connecting(let pInfo):
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Connecting to \(pInfo.name)...")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            case .discoveringServices(let p), .discoveringCharacteristics(let p):
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Discovering \(p.name ?? "device")...")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            case .disconnecting(let pInfo):
                 HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Disconnecting from \(pInfo.name)...")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
            case .idle, .scanningKnown, .scanningPairing:
                if bluetoothManager.knownPeripherals.contains(where: {$0.isConnected}) {
                     // Should not happen if state is idle/scanning but something is connected.
                     // This implies a state mismatch. For now, show generic not connected.
                     Text("Not connected.")
                        .font(.footnote)
                        .foregroundColor(.red)
                } else {
                    Text("Not connected. Add or select a FlySight.")
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
        }
        .frame(height: 20) // Give it a consistent height
    }
}

struct KnownPeripheralRow: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager
    let peripheralInfo: FlySightCore.PeripheralInfo
    let onForget: (FlySightCore.PeripheralInfo) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(peripheralInfo.name)
                    .fontWeight(peripheralInfo.id == bluetoothManager.connectedPeripheralInfo?.id ? .bold : .regular)

                HStack(spacing: 5) {
                    if peripheralInfo.id == bluetoothManager.connectedPeripheralInfo?.id {
                        if case .connected = bluetoothManager.connectionState {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Connected").font(.caption).foregroundColor(.green)
                        } else if case .connecting = bluetoothManager.connectionState {
                             Image(systemName: "ellipsis.circle").foregroundColor(.orange)
                             Text("Connecting...").font(.caption).foregroundColor(.orange)
                        } else if case .discoveringServices = bluetoothManager.connectionState, case .discoveringCharacteristics = bluetoothManager.connectionState {
                             Image(systemName: "ellipsis.circle").foregroundColor(.orange)
                             Text("Finalizing...").font(.caption).foregroundColor(.orange)
                        }
                    } else {
                        Image(systemName: "circle").foregroundColor(.gray) // Placeholder for not connected
                        Text("RSSI: \(peripheralInfo.rssi)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .contentShape(Rectangle()) // Make the VStack tappable
            .onTapGesture {
                handleConnectionTap()
            }

            Spacer()

            if peripheralInfo.id == bluetoothManager.connectedPeripheralInfo?.id {
                // If it's the currently connected one (or trying to connect to it)
                if case .connected = bluetoothManager.connectionState {
                    Button("Disconnect") {
                        bluetoothManager.disconnect(from: peripheralInfo)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.orange)
                } else if case .connecting = bluetoothManager.connectionState {
                    Button("Cancel") { // Cancel ongoing connection attempt
                        bluetoothManager.disconnect(from: peripheralInfo) // disconnect also cancels connection
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.orange)
                }
            } else {
                // Not the currently connected one
                Button("Connect") {
                    bluetoothManager.connect(to: peripheralInfo)
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
                .disabled(isConnectionInProgressToAnotherDevice())
            }

            // Forget Button
            Button(action: {
                onForget(peripheralInfo)
            }) {
                Image(systemName: "xmark.circle.fill") // More subtle than minus
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, 8)
        }
        .padding(.vertical, 5)
    }

    private func handleConnectionTap() {
        if peripheralInfo.id == bluetoothManager.connectedPeripheralInfo?.id {
            if case .connected = bluetoothManager.connectionState {
                bluetoothManager.disconnect(from: peripheralInfo)
            }
            // If connecting, tapping again could cancel, but button is clearer.
        } else {
            if !isConnectionInProgressToAnotherDevice() {
                bluetoothManager.connect(to: peripheralInfo)
            }
        }
    }

    private func isConnectionInProgressToAnotherDevice() -> Bool {
        switch bluetoothManager.connectionState {
        case .connecting(let target):
            return target.id != peripheralInfo.id
        case .discoveringServices(let p), .discoveringCharacteristics(let p):
            return p.identifier != peripheralInfo.id
        default:
            return false
        }
    }
}

// Preview needs careful setup for BluetoothManager states
struct ConnectView_Previews: PreviewProvider {
    static var previews: some View {
        let mockBm = FlySightCore.BluetoothManager()
        // mockBm.knownPeripherals = [ ... ]
        // mockBm.connectionState = .idle or .connected(to: mockBm.knownPeripherals[0])
        ConnectView(bluetoothManager: mockBm)
    }
}
