import SwiftUI
import SwiftData

struct ManualWeightEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [UserSettings]

    @State private var weight: Double = 70.0
    @State private var date: Date = Date()
    @State private var initialized = false

    private var weightUnit: WeightUnit {
        settings.first?.preferredWeightUnit ?? .kg
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("体重") {
                    HStack {
                        TextField("体重", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title)
                        Text(weightUnit.shortName)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("日期") {
                    DatePicker("记录日期", selection: $date, in: ...Date(), displayedComponents: .date)
                }

                Section {
                    Button("保存") {
                        saveWeight()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.blue)
                }
            }
            .navigationTitle("记录体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if !initialized {
                    // Set default weight based on unit
                    weight = weightUnit == .lb ? 154.0 : 70.0
                    initialized = true
                }
            }
        }
    }

    private func saveWeight() {
        // Convert to kg for storage
        let weightInKg = weightUnit.toKg(weight)
        let entry = WeightEntry(weight: weightInKg, date: date, source: "manual")
        modelContext.insert(entry)
        dismiss()
    }
}

#Preview {
    ManualWeightEntryView()
        .modelContainer(for: [WeightEntry.self, UserSettings.self], inMemory: true)
}
