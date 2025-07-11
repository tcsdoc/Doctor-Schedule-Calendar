# Doctor Schedule Calendar

An iOS application to manage and view a doctor's schedule on a monthly basis.

## Capabilities

*   **12-Month Calendar View**: Displays a full year's calendar, starting from the current month.
*   **Daily Schedule Entry**: For each day, you can input up to three lines of schedule information (up to 16 characters per line).
*   **Monthly Notes**: Each month has a dedicated section for up to three lines of notes.
*   **Auto-Saving**: All schedule information and notes are automatically saved as you type.
*   **Printable Schedule**: Generate a formatted HTML of the entire 12-month schedule and print it using AirPrint.
*   **Today's Date Highlighted**: The current date is highlighted in red for easy identification.

## Project Structure

The project is a standard SwiftUI application with Core Data persistence.

*   `Doctor Schedule Calendar/`
    *   `Doctor_Schedule_CalendarApp.swift`: The main entry point of the application.
    *   `ContentView.swift`: Contains the main UI of the application, including the calendar view, daily schedule entry, and monthly notes.
    *   `Persistence.swift`: Sets up the Core Data stack and provides sample data for SwiftUI previews.
    *   `Doctor_Schedule_Calendar.xcdatamodeld`: The Core Data model file defining the `DailySchedule` and `MonthlyNotes` entities.
    *   `Assets.xcassets`: Contains app icons and colors.
*   `Doctor Schedule Calendar.xcodeproj`: The Xcode project file.

### Data Model

The application uses Core Data to store the schedule information. The data model consists of two main entities:

*   **`DailySchedule`**: Represents the schedule for a single day.
    *   `date`: The date of the schedule entry.
    *   `line1`, `line2`, `line3`: Three string fields for the schedule details.
*   **`MonthlyNotes`**: Represents the notes for a single month.
    *   `month`: The month number.
    *   `year`: The year.
    *   `line1`, `line2`, `line3`: Three string fields for the notes.

## How to Run

1.  Clone the repository.
2.  Open `Doctor Schedule Calendar.xcodeproj` in Xcode.
3.  Select a simulator or a connected device.
4.  Click the "Run" button (or press `Cmd+R`).