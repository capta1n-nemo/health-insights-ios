import SwiftUI
import InsightKit

/// **One bottle: its name, its Supplement Facts panel, and how much you take.**
///
/// Deliberately not named `…Sheet`: it is presented from
/// `SupplementStackSheet`, which is the surface the master input list opens, and
/// `verify.sh` requires every `…Sheet` under `Features/` to be reachable from
/// `AddDataView`. One input, one entry point — see `InputKind.supplement`.
///
/// ## The three amount shapes, on the screen rather than in the model alone
///
/// A row can say a number, say "it is inside a proprietary blend", or say
/// nothing at all — and the second two are the reason this feature is worth
/// building carefully. The picker makes the reader choose between them, because
/// the alternative is a blank field that the app would have to interpret, and
/// the only two available interpretations are "nought" and "unknown".
struct SupplementProductEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// The entry being edited, or `nil` for a new bottle.
    let entry: SupplementEntry?

    @State private var name = ""
    @State private var brand = ""
    @State private var servingDescription = ""
    @State private var servingsPerDay = 1.0
    @State private var ingredients: [SupplementIngredient] = []
    @State private var stoppedOn: Date?
    @State private var isStopped = false

    var body: some View {
        NavigationStack {
            Form {
                Section("The bottle") {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    TextField("One serving is (optional)", text: $servingDescription)
                }

                Section {
                    Stepper(value: $servingsPerDay, in: 0.25...12, step: 0.25) {
                        LabeledContent("Servings a day",
                                       value: SupplementFormatting.number(servingsPerDay))
                    }
                    Toggle("I have stopped taking this", isOn: $isStopped)
                } footer: {
                    Text("Everything below is per serving, as the label states "
                         + "it. The totals multiply by your servings a day, not "
                         + "by the label's suggestion.")
                }

                ingredientSection

                if entry != nil {
                    Section {
                        Button("Remove this supplement", role: .destructive) {
                            if let entry { model.deleteSupplementEntry(id: entry.id) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Add a supplement" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder private var ingredientSection: some View {
        Section {
            ForEach($ingredients) { $ingredient in
                SupplementIngredientEditor(ingredient: $ingredient)
            }
            .onDelete { ingredients.remove(atOffsets: $0) }

            Button {
                ingredients.append(SupplementIngredient(
                    nutrient: nil, labelText: "", amount: .notStated))
            } label: {
                Label("Add an ingredient", systemImage: "plus.circle")
            }
        } header: {
            Text("Supplement Facts")
        } footer: {
            Text("Add every line you want counted. A line the app does not "
                 + "recognise as a nutrient with a published limit — a herb, an "
                 + "amino acid, a probiotic — is still kept and shown, it is "
                 + "just not weighed against anything, because there is nothing "
                 + "published to weigh it against.")
        }
    }

    private func load() {
        guard let entry else { return }
        name = entry.product.name
        brand = entry.product.brand ?? ""
        servingDescription = entry.product.servingDescription ?? ""
        servingsPerDay = entry.servingsPerDay
        ingredients = entry.product.ingredients
        stoppedOn = entry.stoppedOn
        isStopped = entry.stoppedOn != nil
    }

    private func save() {
        let product = SupplementProduct(
            id: entry?.product.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.isEmpty ? nil : brand,
            servingDescription: servingDescription.isEmpty ? nil : servingDescription,
            ingredients: ingredients.filter {
                !($0.labelText.trimmingCharacters(in: .whitespaces).isEmpty
                  && $0.nutrient == nil)
            },
            source: entry?.product.source ?? .typedByReader,
            addedAt: entry?.product.addedAt ?? Date())
        model.saveSupplementEntry(SupplementEntry(
            id: entry?.id ?? UUID(),
            product: product,
            servingsPerDay: servingsPerDay,
            startedOn: entry?.startedOn ?? Date(),
            // Keep the date they actually stopped when one is already recorded;
            // only stamp today when the toggle is being turned on now.
            stoppedOn: isStopped ? (stoppedOn ?? Date()) : nil))
        dismiss()
    }
}

/// One line of a Supplement Facts panel.
struct SupplementIngredientEditor: View {
    @Binding var ingredient: SupplementIngredient

    /// Which of the three amount shapes this line is.
    private enum Shape: String, CaseIterable, Identifiable {
        case stated = "Amount"
        case blend = "In a blend"
        case unstated = "Not stated"
        var id: String { rawValue }
    }

    @State private var shape: Shape = .stated
    @State private var value = ""
    @State private var unit: NutrientUnit = .milligrams
    @State private var form: NutrientForm?
    @State private var blendName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("As the label writes it", text: $ingredient.labelText)

            Picker("Nutrient", selection: nutrientBinding) {
                Text("Not one the app can weigh").tag(Nutrient?.none)
                ForEach(Nutrient.allCases) { nutrient in
                    Text(nutrient.displayName).tag(Nutrient?.some(nutrient))
                }
            }

            if ingredient.nutrient != nil {
                Picker("", selection: $shape) {
                    ForEach(Shape.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch shape {
                case .stated:
                    HStack {
                        TextField("Amount", text: $value)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $unit) {
                            ForEach(NutrientUnit.allCases, id: \.self) {
                                Text($0.symbol).tag($0)
                            }
                        }
                        .labelsHidden()
                    }
                    // ⚠️ Only where it changes the answer. An IU figure for
                    // vitamin D converts without knowing the form; for A and E
                    // it cannot be converted at all without one, and the app
                    // says so rather than picking.
                    if unit == .internationalUnits {
                        Picker("Form", selection: $form) {
                            Text("Not stated on the label").tag(NutrientForm?.none)
                            ForEach(NutrientForm.allCases, id: \.self) {
                                Text($0.displayName).tag(NutrientForm?.some($0))
                            }
                        }
                        Text("A label giving IU without naming the form cannot be "
                             + "converted honestly — natural and synthetic vitamin E "
                             + "differ by half again, and only preformed vitamin A "
                             + "counts toward its limit. Left unnamed, this line is "
                             + "carried as unknown rather than guessed at.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                case .blend:
                    TextField("Blend name, as the label writes it", text: $blendName)
                    HStack {
                        TextField("Blend total (optional)", text: $value)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $unit) {
                            ForEach(NutrientUnit.allCases, id: \.self) {
                                Text($0.symbol).tag($0)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("The blend's total is not this ingredient's amount, and "
                         + "the app will not divide one into the other. This line "
                         + "is counted as unknown, and every total it is part of "
                         + "is shown as \"at least\".")
                        .font(.caption2).foregroundStyle(.tertiary)
                case .unstated:
                    Text("Listed with no amount. Counted as unknown, never as nought.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear(perform: load)
        .onChange(of: shape) { _, _ in commit() }
        .onChange(of: value) { _, _ in commit() }
        .onChange(of: unit) { _, _ in commit() }
        .onChange(of: form) { _, _ in commit() }
        .onChange(of: blendName) { _, _ in commit() }
    }

    private var nutrientBinding: Binding<Nutrient?> {
        Binding(get: { ingredient.nutrient },
                set: { ingredient.nutrient = $0; commit() })
    }

    private func load() {
        switch ingredient.amount {
        case .stated(let amount):
            shape = .stated
            value = SupplementFormatting.number(amount.value)
            unit = amount.unit
            form = amount.form
        case .withinProprietaryBlend(let name, let total):
            shape = .blend
            blendName = name
            value = total.map { SupplementFormatting.number($0.value) } ?? ""
            unit = total?.unit ?? .milligrams
        case .notStated:
            shape = .unstated
        }
    }

    private func commit() {
        let parsed = Double(value.replacingOccurrences(of: ",", with: "."))
        switch shape {
        case .stated:
            // An empty or unparseable field is `notStated`, never nought: a
            // reader mid-typing has not declared that the bottle contains none.
            guard let parsed else {
                ingredient.amount = .notStated
                return
            }
            ingredient.amount = .stated(NutrientAmount(value: parsed, unit: unit, form: form))
        case .blend:
            ingredient.amount = .withinProprietaryBlend(
                blendName: blendName.isEmpty ? "proprietary" : blendName,
                blendTotal: parsed.map { NutrientAmount(value: $0, unit: unit) })
        case .unstated:
            ingredient.amount = .notStated
        }
    }
}
