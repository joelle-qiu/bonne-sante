import SwiftUI
import SwiftData

/// 训练 Tab：体态目标、训练计划与提醒
/// @author jiali.qiu
struct TasksTabView: View {
    @Query(sort: \TodoItem.dueDate) private var todos: [TodoItem]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var showAdd = false
    @State private var newTitle = ""
    @State private var newDueDate = Date()

    private var fitnessTodos: [TodoItem] {
        todos.filter { $0.sourceType.isFitnessTask }
    }

    private var openTodos: [TodoItem] {
        fitnessTodos.filter { !$0.isCompleted }
    }

    private var completedTodos: [TodoItem] {
        fitnessTodos.filter(\.isCompleted)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        GoalsView()
                    } label: {
                        Label("减脂目标", systemImage: "target")
                    }
                }

                if !openTodos.isEmpty {
                    Section("训练计划") {
                        ForEach(openTodos, id: \.id) { item in
                            TodoRow(item: item, onToggle: {
                                toggleComplete(item)
                            }, onPostpone: {
                                postpone(item)
                            })
                        }
                        .onDelete { indexSet in
                            deleteItems(at: indexSet, from: openTodos)
                        }
                    }
                }

                if !completedTodos.isEmpty {
                    Section("已完成") {
                        ForEach(completedTodos, id: \.id) { item in
                            TodoRow(item: item, isCompleted: true, onToggle: {
                                toggleComplete(item)
                            })
                        }
                        .onDelete { indexSet in
                            deleteItems(at: indexSet, from: completedTodos)
                        }
                    }
                }

                if openTodos.isEmpty && completedTodos.isEmpty {
                    Section("训练计划") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("暂无训练计划")
                                .font(.subheadline.weight(.medium))
                            Text("添加跑步、力量训练等，到期会收到本地提醒。体检复查请在「健康 → 复查提醒」设置。")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(Theme.pageBackground(colorScheme).ignoresSafeArea())
            .navigationTitle("训练")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                addSheet
            }
            .task {
                await TodoService.requestAuthorization()
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                TextField("训练内容", text: $newTitle, prompt: Text("例如：深蹲 3 组 × 12 次"))
                DatePicker("提醒时间", selection: $newDueDate, displayedComponents: [.date, .hourAndMinute])
            }
            .navigationTitle("新建训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showAdd = false
                        resetForm()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveNew()
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func saveNew() {
        let item = TodoItem(
            title: newTitle.trimmingCharacters(in: .whitespaces),
            dueDate: newDueDate,
            source: .fitness
        )
        modelContext.insert(item)
        try? modelContext.save()
        TodoService.scheduleReminders(for: item)
        showAdd = false
        resetForm()
    }

    private func resetForm() {
        newTitle = ""
        newDueDate = Date()
    }

    private func toggleComplete(_ item: TodoItem) {
        item.isCompleted.toggle()
        try? modelContext.save()
        if item.isCompleted {
            TodoService.cancelNotifications(for: item.id)
        } else {
            TodoService.scheduleReminders(for: item)
        }
    }

    private func postpone(_ item: TodoItem) {
        item.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: item.dueDate) ?? item.dueDate
        try? modelContext.save()
        TodoService.scheduleReminders(for: item)
    }

    private func deleteItems(at offsets: IndexSet, from list: [TodoItem]) {
        for index in offsets {
            let item = list[index]
            TodoService.cancelNotifications(for: item.id)
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}

private struct TodoRow: View {
    let item: TodoItem
    var isCompleted: Bool = false
    let onToggle: () -> Void
    var onPostpone: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleted ? Theme.primary : Theme.textSecondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .strikethrough(isCompleted)
                Text(item.dueDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let onPostpone, !isCompleted {
                Button("改天") { onPostpone() }
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TasksTabView()
        .modelContainer(for: [TodoItem.self, UserGoal.self, WeightEntry.self], inMemory: true)
}
