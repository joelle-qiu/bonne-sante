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
        todos.filter { $0.sourceType.isFitnessTask && $0.seriesKey.isEmpty }
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
                    NavigationLink {
                        WorkoutPlanView()
                    } label: {
                        Label("训练计划", systemImage: "figure.run")
                    }
                    NavigationLink {
                        WorkoutCalendarView()
                    } label: {
                        Label("运动日历", systemImage: "calendar")
                    }
                }

                if !openTodos.isEmpty {
                    Section("其他训练提醒") {
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
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("从这里开始", systemImage: "figure.run")
                                .font(.subheadline.weight(.semibold))
                            Text("设置减脂目标并生成周训练计划；门诊预约请在「健康」Tab 导入。")
                                .font(.caption)
                                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .cycleThemedPageBackground()
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
            if !item.calendarEventIdentifier.isEmpty {
                try? CalendarService.removeEvent(identifier: item.calendarEventIdentifier)
            }
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}

struct AppointmentTodoRow: View {
    let item: TodoItem
    var isCompleted: Bool = false
    let onToggle: () -> Void
    var onAddCalendar: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleted ? Theme.adaptiveAccent(colorScheme) : Theme.adaptiveTextSecondary(colorScheme))
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .strikethrough(isCompleted)
                if !item.department.isEmpty {
                    Text(item.department)
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
                Text(item.dueDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                if let location = item.location, !location.isEmpty {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }
            Spacer()
            if let onAddCalendar, !isCompleted, item.calendarEventIdentifier.isEmpty {
                Button {
                    onAddCalendar()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .buttonStyle(.borderless)
            } else if !item.calendarEventIdentifier.isEmpty {
                Image(systemName: "calendar")
                    .foregroundStyle(Theme.adaptiveAccent(colorScheme))
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
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
        .modelContainer(for: [TodoItem.self, UserGoal.self, WeightEntry.self, WorkoutPlanEntry.self, WorkoutPlanPreferences.self], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
