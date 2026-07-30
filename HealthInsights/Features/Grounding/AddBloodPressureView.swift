import SwiftUI
import InsightKit

/// Entry sheet for a single dated reading. Plain numeric fields (no steppers) and
/// one clear Save action at the bottom.
struct AddBloodPressureView: View {
    let onSave: (Double, Double, Date) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var systolicText = ""
    @State private var diastolicText = ""
    @State private var date = Date()

    private var systolic: Double? {
        Double(systolicText.trimmingCharacters(in: .whitespaces))
    }
    private var diastolic: Double? {
        Double(diastolicText.trimmingCharacters(in: .whitespaces))
    }

    /// A reading is valid only when both numbers are present, in a plausible
    /// range, and systolic is above diastolic.
    private var isValid: Bool {
        guard let s = systolic, let d = diastolic else { return false }
        return (60...260).contains(s) && (30...200).contains(d) && s > d
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Systolic")
                        Spacer()
                        TextField("120", text: $systolicText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("mmHg").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Diastolic")
                        Spacer()
                        TextField("80", text: $diastolicText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("mmHg").foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $date, in: ...Date())
                } footer: {
                    if let s = systolic, let d = diastolic, isValid {
                        Text("Category: \(BloodPressureEstimator.category(systolic: s, diastolic: d)). Use a real upper-arm cuff, seated and rested.")
                    } else {
                        Text("Enter the two numbers your cuff shows (the higher one is systolic). Use a real upper-arm cuff, seated and rested.")
                    }
                }

                Section {
                    Button {
                        if let s = systolic, let d = diastolic { onSave(s, d, date); dismiss() }
                    } label: {
                        Text("Save reading").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                }
            }
            .navigationTitle("Add reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
