import OfflineFirstFramework
import SwiftUI

struct TodoListView: View {
    @Bindable var model: DemoModel
    @State private var newTitle = ""

    private var todos: SyncedCollection<Todo> { model.todos }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("New to-do", text: $newTitle)
                        .onSubmit {
                            let title = newTitle
                            newTitle = ""
                            Task { await model.add(title) }
                        }
                    ForEach(todos.records) { todo in
                        TodoRow(todo: todo) {
                            Task { await model.toggle(todo) }
                        }
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { todos.records[$0] }
                        Task {
                            for todo in removed { await model.delete(todo) }
                        }
                    }
                }

                Section("Sync") {
                    SyncStatusRow(status: todos.status, pendingCount: todos.pendingCount, failedCount: todos.failedCount,
                                  lastSyncedAt: todos.lastSyncedAt)
                    Toggle("Online", isOn: Binding(get: { model.isOnline }, set: { model.setOnline($0) }))
                        .tint(.accentColor)
                    Button("Edit on another device") {
                        Task { await model.editOnOtherDevice() }
                    }
                    if let message = model.otherDeviceMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let error = todos.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Offline To-dos")
            .toolbar {
                Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await todos.sync() }
                }
                .disabled(todos.status == .syncing)
            }
            .refreshable { await todos.sync() }
        }
    }
}

private struct TodoRow: View {
    let todo: Todo
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Label {
                Text(todo.title)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
            } icon: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isDone ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(todo.isDone ? "Done" : "Not done")
    }
}

private struct SyncStatusRow: View {
    let status: SyncStatus
    let pendingCount: Int
    let failedCount: Int
    let lastSyncedAt: Date?

    var body: some View {
        LabeledContent {
            Text(detail)
                .multilineTextAlignment(.trailing)
        } label: {
            Label(title, systemImage: symbol)
        }
    }

    private var title: String {
        switch status {
        case .idle: pendingCount == 0 ? "Up to date" : "Waiting to sync"
        case .syncing: "Syncing…"
        case .offline: "Offline"
        case .paused: "Paused after errors"
        case .failed: "Sync failed"
        }
    }

    private var symbol: String {
        switch status {
        case .idle: pendingCount == 0 ? "checkmark.icloud" : "icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .offline: "icloud.slash"
        case .paused, .failed: "exclamationmark.icloud"
        }
    }

    private var detail: String {
        var parts: [String] = []
        if pendingCount > 0 { parts.append(pendingCount == 1 ? "1 change waiting" : "\(pendingCount) changes waiting") }
        if failedCount > 0 { parts.append("\(failedCount) failed") }
        if parts.isEmpty, let lastSyncedAt { parts.append(lastSyncedAt.formatted(date: .omitted, time: .shortened)) }
        return parts.joined(separator: ", ")
    }
}
