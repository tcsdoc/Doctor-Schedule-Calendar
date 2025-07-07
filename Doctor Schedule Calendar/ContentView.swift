//
//  ContentView.swift
//  Doctor Schedule Calendar
//
//  Created by mark on 7/5/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Doctor.name, ascending: true)],
        animation: .default)
    private var doctors: FetchedResults<Doctor>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Appointment.startDate, ascending: true)],
        predicate: NSPredicate(format: "startDate >= %@", Calendar.current.startOfDay(for: Date()) as NSDate),
        animation: .default)
    private var upcomingAppointments: FetchedResults<Appointment>

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Doctors Tab
            NavigationView {
                List {
                    ForEach(doctors) { doctor in
                        NavigationLink {
                            DoctorDetailView(doctor: doctor)
                        } label: {
                            DoctorRowView(doctor: doctor)
                        }
                    }
                    .onDelete(perform: deleteDoctors)
                }
                .navigationTitle("Doctors")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                    ToolbarItem {
                        Button(action: addDoctor) {
                            Label("Add Doctor", systemImage: "plus")
                        }
                    }
                }
            }
            .tabItem {
                Image(systemName: "stethoscope")
                Text("Doctors")
            }
            .tag(0)
            
            // Appointments Tab
            NavigationView {
                List {
                    if upcomingAppointments.isEmpty {
                        Text("No upcoming appointments")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(upcomingAppointments) { appointment in
                            NavigationLink {
                                AppointmentDetailView(appointment: appointment)
                            } label: {
                                AppointmentRowView(appointment: appointment)
                            }
                        }
                        .onDelete(perform: deleteAppointments)
                    }
                }
                .navigationTitle("Appointments")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                    ToolbarItem {
                        Button(action: addAppointment) {
                            Label("Add Appointment", systemImage: "plus")
                        }
                    }
                }
            }
            .tabItem {
                Image(systemName: "calendar")
                Text("Appointments")
            }
            .tag(1)
        }
    }

    private func addDoctor() {
        withAnimation {
            let newDoctor = Doctor(context: viewContext)
            newDoctor.id = UUID()
            newDoctor.name = "New Doctor"
            newDoctor.specialization = "General Practice"

            do {
                try viewContext.save()
            } catch {
                // Handle the error appropriately
                let nsError = error as NSError
                print("Error adding doctor: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func addAppointment() {
        withAnimation {
            guard let firstDoctor = doctors.first else {
                // If no doctors exist, create one first
                addDoctor()
                return
            }
            
            let newAppointment = Appointment(context: viewContext)
            newAppointment.id = UUID()
            newAppointment.title = "New Appointment"
            newAppointment.startDate = Date()
            newAppointment.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
            newAppointment.doctor = firstDoctor

            do {
                try viewContext.save()
            } catch {
                // Handle the error appropriately
                let nsError = error as NSError
                print("Error adding appointment: \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteDoctors(offsets: IndexSet) {
        withAnimation {
            offsets.map { doctors[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                // Handle the error appropriately
                let nsError = error as NSError
                print("Error deleting doctor: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func deleteAppointments(offsets: IndexSet) {
        withAnimation {
            offsets.map { upcomingAppointments[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                // Handle the error appropriately
                let nsError = error as NSError
                print("Error deleting appointment: \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct DoctorRowView: View {
    let doctor: Doctor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(doctor.name ?? "Unknown Doctor")
                .font(.headline)
            Text(doctor.specialization ?? "Unknown Specialization")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let appointmentCount = doctor.appointments?.count, appointmentCount > 0 {
                Text("\(appointmentCount) appointment\(appointmentCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }
}

struct AppointmentRowView: View {
    let appointment: Appointment
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appointment.title ?? "Unknown Appointment")
                .font(.headline)
            if let patientName = appointment.patientName {
                Text("Patient: \(patientName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text(dateFormatter.string(from: appointment.startDate ?? Date()))
                    .font(.caption)
                Text(timeFormatter.string(from: appointment.startDate ?? Date()))
                    .font(.caption)
                    .foregroundColor(.blue)
                Spacer()
                Text(appointment.doctor?.name ?? "Unknown Doctor")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct DoctorDetailView: View {
    let doctor: Doctor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Doctor Details")
                .font(.largeTitle)
                .bold()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Name: \(doctor.name ?? "Unknown")")
                Text("Specialization: \(doctor.specialization ?? "Unknown")")
                if let email = doctor.email {
                    Text("Email: \(email)")
                }
                if let phone = doctor.phone {
                    Text("Phone: \(phone)")
                }
            }
            .font(.body)
            
            Spacer()
        }
        .padding()
        .navigationTitle(doctor.name ?? "Doctor")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppointmentDetailView: View {
    let appointment: Appointment
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appointment Details")
                .font(.largeTitle)
                .bold()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Title: \(appointment.title ?? "Unknown")")
                if let patientName = appointment.patientName {
                    Text("Patient: \(patientName)")
                }
                Text("Doctor: \(appointment.doctor?.name ?? "Unknown")")
                Text("Start: \(dateFormatter.string(from: appointment.startDate ?? Date()))")
                Text("End: \(dateFormatter.string(from: appointment.endDate ?? Date()))")
                if let notes = appointment.notes, !notes.isEmpty {
                    Text("Notes: \(notes)")
                }
            }
            .font(.body)
            
            Spacer()
        }
        .padding()
        .navigationTitle(appointment.title ?? "Appointment")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
