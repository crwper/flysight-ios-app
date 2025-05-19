//
//  StartingPistolView.swift
//  FlySight
//
//  Created by Michael Cooper on 2025-05-19.
//

import SwiftUI
import FlySightCore

// ViewModel for storing recent start dates persistently
class StartingPistolViewModel: ObservableObject {
    @Published var recentStartDates: [Date] = [] {
        didSet {
            saveRecentStartDates()
        }
    }
    private let recentStartDatesKey = "recentStartDates_v1" // Use a versioned key if format changes

    init() {
        loadRecentStartDates()
    }

    private func saveRecentStartDates() {
        let datesAsTimeIntervals = recentStartDates.map { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(datesAsTimeIntervals, forKey: recentStartDatesKey)
    }

    private func loadRecentStartDates() {
        if let datesAsTimeIntervals = UserDefaults.standard.array(forKey: recentStartDatesKey) as? [TimeInterval] {
            recentStartDates = datesAsTimeIntervals.map { Date(timeIntervalSince1970: $0) }.sorted(by: >) // Sort on load
        }
    }

    func clearRecentStartDates() {
        recentStartDates.removeAll()
        // UserDefaults will be updated by the didSet observer
    }

    func addNewStartDate(_ date: Date) {
        if !recentStartDates.contains(date) { // Avoid duplicates if possible (though exact ms match is rare)
            recentStartDates.insert(date, at: 0) // Add to top
            recentStartDates.sort(by: >) // Keep sorted descending
            if recentStartDates.count > 50 { // Limit stored history
                recentStartDates.removeLast(recentStartDates.count - 50)
            }
        }
    }
}


struct StartingPistolView: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager
    @StateObject private var viewModel = StartingPistolViewModel() // Handles persistent storage

    @State private var showingClearAlert = false
    @State private var copiedDate: Date? // For visual feedback on copy

    var body: some View {
        NavigationView {
            VStack {
                if case .connected = bluetoothManager.connectionState {
                    Text("Recent Start Times (UTC)")
                        .font(.headline)
                        .padding(.top)

                    if viewModel.recentStartDates.isEmpty {
                        Text("No start times recorded yet using the app.\nStart results from the device itself (button press) are not shown here.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else {
                        List {
                            ForEach(viewModel.recentStartDates, id: \.self) { date in
                                HStack {
                                    Text(formatDate(date))
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Button {
                                        UIPasteboard.general.string = formatDate(date)
                                        copiedDate = date
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            if copiedDate == date { // Ensure it's still the one we meant to clear highlight for
                                                copiedDate = nil
                                            }
                                        }
                                    } label: {
                                        Image(systemName: copiedDate == date ? "doc.on.doc.fill" : "doc.on.doc")
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.vertical, 4)
                                .listRowBackground(copiedDate == date ? Color.green.opacity(0.2) : Color(UIColor.systemGroupedBackground))
                                .animation(.easeInOut(duration: 0.2), value: copiedDate)
                            }
                        }
                        .listStyle(InsetGroupedListStyle())
                    }

                    Spacer()

                    // Control Buttons
                    HStack(spacing: 20) {
                        Button(action: {
                            bluetoothManager.sendStartCommand()
                        }) {
                            Text("Start Countdown")
                                .fontWeight(.semibold)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(bluetoothManager.startPistolState == .idle ? Color.blue : Color.gray.opacity(0.5))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(bluetoothManager.startPistolState != .idle)

                        Button(action: {
                            bluetoothManager.sendCancelCommand()
                        }) {
                            Text("Cancel")
                                .fontWeight(.semibold)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(bluetoothManager.startPistolState == .counting ? Color.red : Color.gray.opacity(0.5))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(bluetoothManager.startPistolState != .counting)
                    }
                    .padding()
                    .padding(.bottom, 10)

                    // Status
                    Text(statusMessage())
                        .font(.caption)
                        .foregroundColor(statusMessageColor())
                        .frame(height: 30)

                } else { // Not connected
                    Spacer()
                    Image(systemName: "timer.square")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                        .padding(.bottom)
                    Text("Not Connected")
                        .font(.headline)
                    Text("Connect to a FlySight to use the Starting Pistol feature.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
            }
            .navigationTitle("Starting Pistol")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingClearAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(viewModel.recentStartDates.isEmpty)
                }
            }
            .alert(isPresented: $showingClearAlert) {
                Alert(
                    title: Text("Clear History"),
                    message: Text("Are you sure you want to clear all recent start times?"),
                    primaryButton: .destructive(Text("Clear")) {
                        viewModel.clearRecentStartDates()
                    },
                    secondaryButton: .cancel()
                )
            }
            .onReceive(bluetoothManager.$startResultDate) { date in
                if let validDate = date {
                    viewModel.addNewStartDate(validDate)
                    bluetoothManager.startResultDate = nil // Clear it after processing
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC as per FlySight doc for SP_Result
        return formatter.string(from: date)
    }

    private func statusMessage() -> String {
        switch bluetoothManager.startPistolState {
        case .idle:
            return "Ready to start."
        case .counting:
            return "Countdown active..."
        }
    }

    private func statusMessageColor() -> Color {
        switch bluetoothManager.startPistolState {
        case .idle:
            return .green
        case .counting:
            return .orange
        }
    }
}

struct StartingPistolView_Previews: PreviewProvider {
    static var previews: some View {
        let mockBm = FlySightCore.BluetoothManager()
        // mockBm.connectionState = .connected(to: ...)
        // mockBm.startPistolState = .idle or .counting
        // let vm = StartingPistolViewModel()
        // vm.recentStartDates = [Date(), Date().addingTimeInterval(-1000)]
        StartingPistolView(bluetoothManager: mockBm/*, viewModel: vm*/) // If viewModel was not @StateObject
    }
}
