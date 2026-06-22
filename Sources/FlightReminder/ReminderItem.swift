import Foundation

struct ReminderItem: Identifiable, Hashable {
    let id: String
    let title: String
    let dueDate: Date?
    let listTitle: String
}
