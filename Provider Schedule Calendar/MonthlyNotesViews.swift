// MonthlyNotesViews.swift
// Monthly notes header fields and container wrapper.

import SwiftUI

// MARK: - Redesigned Monthly Notes View (2 Fields)
struct RedesignedMonthlyNotesView: View {
    let month: Date
    let line1: String
    let line2: String
    let onLine1Change: (String) -> Void
    let onLine2Change: (String) -> Void
    let onFocusChange: (Bool) -> Void
    
    @State private var line1Text: String = ""
    @State private var line2Text: String = ""
    @State private var initialized: Bool = false
    @State private var line1LastKnown: String = ""
    @State private var line2LastKnown: String = ""
    @FocusState private var line1Focused: Bool
    @FocusState private var line2Focused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(spacing: 2) {
                // Blue field (Line 1)
                HStack(spacing: 8) {
                    Text("Line 1:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(minWidth: 60, maxWidth: 60, alignment: .leading)
                    
                    TextField("", text: $line1Text)
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocapitalization(.allCharacters)
                        .focused($line1Focused)
        .padding(4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                        .onSubmit {
                            onLine1Change(normalizeProviderText(line1Text))
                        }
                        .onChange(of: line1Text) { _, newValue in
                            let normalized = normalizeProviderText(newValue)
                            if line1Text != normalized {
                                line1Text = normalized
                                return
                            }
                            // Real-time change detection like daily schedule fields
                            if !line1LastKnown.isEmpty || line1Focused {
                                onLine1Change(normalized)
                            }
                            line1LastKnown = normalized
                        }
                }
                
                // Red field (Line 2)
                HStack(spacing: 8) {
                    Text("Line 2:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .frame(minWidth: 60, maxWidth: 60, alignment: .leading)
                    
                    TextField("", text: $line2Text)
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocapitalization(.allCharacters)
                        .focused($line2Focused)
                        .padding(4)
                        .background(Color.red.opacity(0.1))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
            .onSubmit {
                            onLine2Change(normalizeProviderText(line2Text))
                        }
                        .onChange(of: line2Text) { _, newValue in
                            let normalized = normalizeProviderText(newValue)
                            if line2Text != normalized {
                                line2Text = normalized
                                return
                            }
                            // Real-time change detection like daily schedule fields
                            if !line2LastKnown.isEmpty || line2Focused {
                                onLine2Change(normalized)
                            }
                            line2LastKnown = normalized
                        }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        .onAppear {
            if !initialized {
                line1Text = line1
                line2Text = line2
                line1LastKnown = line1
                line2LastKnown = line2
                initialized = true
            }
        }
        .onChange(of: month) { _, _ in
            // Reset when month changes
            line1Text = line1
            line2Text = line2
            line1LastKnown = line1
            line2LastKnown = line2
        }
        .onChange(of: line1) { _, newValue in
            // Update display when data changes from external source
            if initialized && newValue != line1Text {
                line1Text = newValue
            }
        }
        .onChange(of: line2) { _, newValue in
            // Update display when data changes from external source
            if initialized && newValue != line2Text {
                line2Text = newValue
            }
        }
        .onChange(of: line1Focused) { _, _ in
            onFocusChange(line1Focused || line2Focused)
        }
        .onChange(of: line2Focused) { _, _ in
            onFocusChange(line1Focused || line2Focused)
        }
    }
}

// MARK: - Monthly Notes Container
struct MonthlyNotesContainer: View {
    let currentMonth: Date
    @ObservedObject var viewModel: ScheduleViewModel
    let monthKey: String
    
    var body: some View {
        let note = viewModel.monthlyNotes[monthKey]
        
        RedesignedMonthlyNotesView(
            month: currentMonth,
            line1: note?.line1 ?? "",
            line2: note?.line2 ?? "",
            onLine1Change: { newLine1 in
                viewModel.updateMonthlyNotesLine1(for: currentMonth, line1: newLine1)
            },
            onLine2Change: { newLine2 in
                viewModel.updateMonthlyNotesLine2(for: currentMonth, line2: newLine2)
            },
            onFocusChange: { viewModel.editorFocusChanged("notes", isFocused: $0) }
        )
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }
}
