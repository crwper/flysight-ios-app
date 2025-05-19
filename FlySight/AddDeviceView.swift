//
//  AddDeviceView.swift
//  FlySight
//
//  Created by Michael Cooper on 2025-05-19.
//

import SwiftUI
import FlySightCore

struct AddDeviceView: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                InstructionsView() // Keep your existing InstructionsView
                    .padding()

                Divider()

                if case .scanningPairing = bluetoothManager.connectionState {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 5)
                        Text("Scanning for FlySights in pairing mode...")
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
                }


                List {
                    if bluetoothManager.discoveredPairingPeripherals.isEmpty && bluetoothManager.currentScanMode != .pairingMode {
                         Text("Tap 'Start Scan' to search for devices.")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                            .foregroundColor(.gray)
                    } else if bluetoothManager.discoveredPairingPeripherals.isEmpty && bluetoothManager.currentScanMode == .pairingMode && bluetoothManager.connectionState != .scanningPairing {
                        // This case means scan was started but then stopped, or just no devices yet.
                        Text("No FlySights found in pairing mode yet.")
                           .frame(maxWidth: .infinity, alignment: .center)
                           .padding()
                           .foregroundColor(.gray)
                    }

                    ForEach(bluetoothManager.discoveredPairingPeripherals) { peripheralInfo in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(peripheralInfo.name)
                                    .font(.headline)
                                Text("RSSI: \(peripheralInfo.rssi)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            // Show spinner if connecting to this specific peripheral
                            if case .connecting(let target) = bluetoothManager.connectionState, target.id == peripheralInfo.id {
                                ProgressView()
                            } else {
                                Button("Connect & Pair") {
                                    bluetoothManager.stopScanning() // Stop pairing scan
                                    bluetoothManager.connect(to: peripheralInfo)
                                    // The sheet dismissal is handled by ConnectView observing connectionState
                                }
                                .buttonStyle(PlainButtonStyle()) // Use PlainButtonStyle for better control
                                .foregroundColor(.blue)
                                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .background(Color.secondary.opacity(0.15)) // Softer background
                                .cornerRadius(8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Add New FlySight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if bluetoothManager.currentScanMode == .pairingMode {
                            bluetoothManager.stopScanning()
                        }
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if bluetoothManager.currentScanMode == .pairingMode {
                            bluetoothManager.stopScanning()
                        } else {
                            // Clear previous results and start scanning when the button is tapped
                            bluetoothManager.discoveredPairingPeripherals = []
                            bluetoothManager.startScanningForPairingModeDevices()
                        }
                    }) {
                        Text(bluetoothManager.currentScanMode == .pairingMode && bluetoothManager.connectionState == .scanningPairing ? "Stop Scan" : "Start Scan")
                    }
                }
            }
            .onAppear {
                // Start scanning for pairing mode devices when the view appears
                if bluetoothManager.currentScanMode != .pairingMode {
                    bluetoothManager.discoveredPairingPeripherals = [] // Clear old results
                    bluetoothManager.startScanningForPairingModeDevices()
                }
            }
            .onDisappear {
                // Stop scanning for pairing mode devices if it's still active
                // unless we are in the process of connecting to one from this sheet.
                if case .connecting = bluetoothManager.connectionState {
                    // Don't stop scanning if we initiated a connection from this sheet.
                    // The manager will handle stopping scan upon successful connection or failure.
                } else if bluetoothManager.currentScanMode == .pairingMode {
                    bluetoothManager.stopScanning()
                }
            }
        }
    }
}

struct InstructionsView: View { // Assuming this is defined as before
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pairing Instructions:")
                .font(.title3).bold()
            HStack(alignment: .top) {
                Text("1.").bold().frame(width: 20, alignment: .leading)
                Text("Ensure your FlySight 2 is turned OFF (LED is off).")
            }
            HStack(alignment: .top) {
                Text("2.").bold().frame(width: 20, alignment: .leading)
                Text("Quickly press the power button **two times**.")
            }
            HStack(alignment: .top) {
                Text("3.").bold().frame(width: 20, alignment: .leading)
                Text("The **GREEN LED** will pulse slowly. This is Pairing Request Mode and lasts for 30 seconds or until connected.")
            }
             HStack(alignment: .top) {
                Text("4.").bold().frame(width: 20, alignment: .leading)
                Text("Your FlySight should appear below. Tap 'Connect & Pair'.")
            }
            HStack(alignment: .top) {
                Text("5.").bold().frame(width: 20, alignment: .leading)
                Text("Accept the pairing request from iOS when it appears.")
            }
        }
        .padding(.vertical, 5)
    }
}

// AddDeviceView_Previews can be tricky without a fully mocked BluetoothManager.
// You might need to create a specific mock for preview purposes.
struct AddDeviceView_Previews: PreviewProvider {
    static var previews: some View {
        let mockBm = FlySightCore.BluetoothManager()
        // To make preview useful, you could set some discoveredPairingPeripherals
        // mockBm.discoveredPairingPeripherals = [ ... mock PeripheralInfo ... ]
        // mockBm.connectionState = .scanningPairing // To show scanning state
        AddDeviceView(bluetoothManager: mockBm)
    }
}
