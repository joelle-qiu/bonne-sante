import Foundation
import SwiftData

/// 全量 SwiftData 导出 / 导入（JSON 备份，不含 API Key）
/// @author jiali.qiu
enum HealthDataBackupService {

    enum BackupError: LocalizedError {
        case unsupportedFormat(Int)
        case decodeFailed(String)
        case writeFailed
        case importFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let version):
                return "不支持的备份格式版本 \(version)"
            case .decodeFailed(let detail):
                return "无法读取备份文件：\(detail)"
            case .writeFailed:
                return "无法写入备份文件"
            case .importFailed(let detail):
                return "导入失败：\(detail)"
            }
        }
    }

    // MARK: - Export

    /// 导出全部本地数据为 JSON，返回临时文件 URL（供分享/存储）
    static func exportToTemporaryFile(modelContext: ModelContext) throws -> URL {
        let manifest = try buildManifest(modelContext: modelContext)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let datePart = formatter.string(from: Date())
        let fileName = "\(HealthDataBackupManifest.suggestedFilenamePrefix)-\(datePart).\(HealthDataBackupManifest.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func buildManifest(modelContext: ModelContext) throws -> HealthDataBackupManifest.File {
        let foodEntries = try modelContext.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.createdAt)]))
        let foodPreferences = try modelContext.fetch(FetchDescriptor<FoodPreference>())
        let userGoals = try modelContext.fetch(FetchDescriptor<UserGoal>())
        let weightEntries = try modelContext.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))
        let userSettings = try modelContext.fetch(FetchDescriptor<UserSettings>())
        let cycleProfiles = try modelContext.fetch(FetchDescriptor<CycleProfile>())
        let reports = try modelContext.fetch(FetchDescriptor<Report>(sortBy: [SortDescriptor(\.importDate, order: .reverse)]))
        let healthMetrics = try modelContext.fetch(FetchDescriptor<HealthMetric>())
        let riskFlags = try modelContext.fetch(FetchDescriptor<RiskFlag>())
        let checkupPlans = try modelContext.fetch(FetchDescriptor<CheckupPlan>())
        let todoItems = try modelContext.fetch(FetchDescriptor<TodoItem>())
        let chatMessages = try modelContext.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt)]))
        let workoutPrefs = try modelContext.fetch(FetchDescriptor<WorkoutPlanPreferences>())
        let workoutEntries = try modelContext.fetch(FetchDescriptor<WorkoutPlanEntry>())
        let workoutExercises = try modelContext.fetch(FetchDescriptor<WorkoutExercise>())

        return HealthDataBackupManifest.File(
            formatVersion: HealthDataBackupManifest.formatVersion,
            exportedAt: Date(),
            appSchemaVersion: HealthDataBackupManifest.currentSchemaVersion,
            foodEntries: foodEntries.map(mapFoodEntry),
            foodPreferences: foodPreferences.map(mapFoodPreference),
            userGoals: userGoals.map(mapUserGoal),
            weightEntries: weightEntries.map(mapWeightEntry),
            userSettings: userSettings.map(mapUserSettings),
            cycleProfiles: cycleProfiles.map(mapCycleProfile),
            reports: reports.map(mapReport),
            healthMetrics: healthMetrics.map(mapHealthMetric),
            riskFlags: riskFlags.map(mapRiskFlag),
            checkupPlans: checkupPlans.map(mapCheckupPlan),
            todoItems: todoItems.map(mapTodoItem),
            chatMessages: chatMessages.map(mapChatMessage),
            workoutPlanPreferences: workoutPrefs.map(mapWorkoutPlanPreferences),
            workoutPlanEntries: workoutEntries.map(mapWorkoutPlanEntry),
            workoutExercises: workoutExercises.map(mapWorkoutExercise)
        )
    }

    // MARK: - Import

    /// 解析备份文件并返回摘要（确认弹窗用）
    static func previewImport(from url: URL) throws -> (HealthDataBackupManifest.File, HealthDataBackupManifest.ImportSummary) {
        let manifest = try decodeManifest(from: url)
        let summary = HealthDataBackupManifest.ImportSummary(
            foodEntryCount: manifest.foodEntries.count,
            reportCount: manifest.reports.count,
            workoutSessionCount: manifest.workoutPlanEntries.count
        )
        return (manifest, summary)
    }

    /// 用备份覆盖全部本地 SwiftData（不含 Keychain API Key）
    static func importReplacingAll(modelContext: ModelContext, from url: URL) throws -> HealthDataBackupManifest.ImportSummary {
        let manifest = try decodeManifest(from: url)
        try clearAllRecords(modelContext: modelContext)
        try insertAll(modelContext: modelContext, from: manifest)
        try modelContext.save()
        WorkoutMorningReminderService.sync(modelContext: modelContext)
        return HealthDataBackupManifest.ImportSummary(
            foodEntryCount: manifest.foodEntries.count,
            reportCount: manifest.reports.count,
            workoutSessionCount: manifest.workoutPlanEntries.count
        )
    }

    private static func decodeManifest(from url: URL) throws -> HealthDataBackupManifest.File {
        let data: Data
        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            data = try Data(contentsOf: url)
        } else {
            data = try Data(contentsOf: url)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let manifest = try decoder.decode(HealthDataBackupManifest.File.self, from: data)
            guard manifest.formatVersion == HealthDataBackupManifest.formatVersion else {
                throw BackupError.unsupportedFormat(manifest.formatVersion)
            }
            return manifest
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.decodeFailed(error.localizedDescription)
        }
    }

    private static func clearAllRecords(modelContext: ModelContext) throws {
        try modelContext.delete(model: WorkoutExercise.self)
        try modelContext.delete(model: WorkoutPlanEntry.self)
        try modelContext.delete(model: WorkoutPlanPreferences.self)
        try modelContext.delete(model: ChatMessage.self)
        try modelContext.delete(model: TodoItem.self)
        try modelContext.delete(model: CheckupPlan.self)
        try modelContext.delete(model: RiskFlag.self)
        try modelContext.delete(model: HealthMetric.self)
        try modelContext.delete(model: Report.self)
        try modelContext.delete(model: CycleProfile.self)
        try modelContext.delete(model: UserSettings.self)
        try modelContext.delete(model: WeightEntry.self)
        try modelContext.delete(model: UserGoal.self)
        try modelContext.delete(model: FoodPreference.self)
        try modelContext.delete(model: FoodEntry.self)
    }

    private static func insertAll(modelContext: ModelContext, from manifest: HealthDataBackupManifest.File) throws {
        for dto in manifest.foodPreferences {
            let item = FoodPreference(keyword: dto.keyword, defaultDescription: dto.defaultDescription)
            item.id = dto.id
            item.createdAt = dto.createdAt
            item.usageCount = dto.usageCount
            item.defaultGrams = dto.defaultGrams
            item.defaultCalories = dto.defaultCalories
            item.defaultProtein = dto.defaultProtein
            item.defaultCarbs = dto.defaultCarbs
            item.defaultFat = dto.defaultFat
            modelContext.insert(item)
        }

        for dto in manifest.foodEntries {
            let item = FoodEntry(
                rawInput: dto.rawInput,
                foodName: dto.foodName,
                grams: dto.grams,
                calories: dto.calories,
                protein: dto.protein,
                carbohydrates: dto.carbohydrates,
                fat: dto.fat,
                date: dto.createdAt,
                mealType: MealType(rawValue: dto.mealType)
            )
            item.id = dto.id
            item.mealType = dto.mealType
            modelContext.insert(item)
        }

        for dto in manifest.userGoals {
            let item = UserGoal(
                targetWeight: dto.targetWeight,
                height: dto.height,
                age: dto.age,
                gender: dto.gender,
                activityLevel: dto.activityLevel,
                targetDate: dto.targetDate,
                targetBodyFat: dto.targetBodyFat,
                currentBodyFat: dto.currentBodyFat,
                targetLeanBodyMassKg: dto.targetLeanBodyMassKg,
                currentLeanBodyMassKg: dto.currentLeanBodyMassKg
            )
            item.id = dto.id
            item.createdAt = dto.createdAt
            item.updatedAt = dto.updatedAt
            modelContext.insert(item)
        }

        for dto in manifest.weightEntries {
            let item = WeightEntry(weight: dto.weight, date: dto.date, source: dto.source)
            item.id = dto.id
            modelContext.insert(item)
        }

        for dto in manifest.userSettings {
            let item = UserSettings(
                weightUnit: WeightUnit(rawValue: dto.weightUnit) ?? .kg,
                appearanceMode: AppAppearanceMode(rawValue: dto.appearanceMode) ?? .system,
                profileNickname: dto.profileNickname,
                workoutMorningReminderEnabled: dto.workoutMorningReminderEnabled,
                workoutMorningReminderHour: dto.workoutMorningReminderHour,
                workoutMorningReminderMinute: dto.workoutMorningReminderMinute,
                elderModeEnabled: dto.elderModeEnabled
            )
            item.createdAt = dto.createdAt
            modelContext.insert(item)
        }

        if manifest.userSettings.isEmpty {
            modelContext.insert(UserSettings())
        }

        for dto in manifest.cycleProfiles {
            let item = CycleProfile(
                lastPeriodStart: dto.lastPeriodStart,
                averageCycleLength: dto.averageCycleLength,
                averagePeriodLength: dto.averagePeriodLength,
                dataSource: dto.dataSource,
                lastSyncedAt: dto.lastSyncedAt
            )
            modelContext.insert(item)
        }

        var reportById: [UUID: Report] = [:]
        for dto in manifest.reports {
            let item = Report(
                fileName: dto.fileName,
                sourceType: dto.sourceType,
                examDate: dto.examDate,
                isVerified: dto.isVerified,
                rawOCRText: dto.rawOCRText,
                recommendationsText: dto.recommendationsText
            )
            item.id = dto.id
            item.importDate = dto.importDate
            modelContext.insert(item)
            reportById[dto.id] = item
        }

        for dto in manifest.healthMetrics {
            let metric = HealthMetric(
                name: dto.name,
                value: dto.value,
                valueText: dto.valueText,
                unit: dto.unit,
                referenceRange: dto.referenceRange,
                isAbnormal: dto.isAbnormal,
                date: dto.date,
                category: dto.category,
                reportSection: dto.reportSection,
                severityRank: dto.severityRank,
                assessmentNote: dto.assessmentNote,
                morphologyTag: dto.morphologyTag,
                organSiteTag: dto.organSiteTag,
                report: dto.reportId.flatMap { reportById[$0] }
            )
            metric.id = dto.id
            modelContext.insert(metric)
        }

        for dto in manifest.riskFlags {
            let item = RiskFlag(
                metricName: dto.metricName,
                severity: RiskSeverity(rawValue: dto.severity) ?? .low,
                currentValue: dto.currentValue,
                trendDescription: dto.trendDescription,
                suggestedAction: dto.suggestedAction,
                checkupMonths: dto.checkupMonths,
                department: dto.department,
                seriesKey: dto.seriesKey,
                isResolved: dto.isResolved
            )
            item.id = dto.id
            item.createdDate = dto.createdDate
            modelContext.insert(item)
        }

        for dto in manifest.checkupPlans {
            let item = CheckupPlan(
                metricName: dto.metricName,
                department: dto.department,
                seriesKey: dto.seriesKey,
                frequencyInMonths: dto.frequencyInMonths,
                lastExamDate: dto.lastExamDate,
                reminderDaysBefore: dto.reminderDaysBefore
            )
            item.id = dto.id
            item.nextDueDate = dto.nextDueDate
            modelContext.insert(item)
        }

        for dto in manifest.todoItems {
            let item = TodoItem(
                title: dto.title,
                dueDate: dto.dueDate,
                location: dto.location,
                notes: dto.notes,
                source: TodoSource(rawValue: dto.source) ?? .manual,
                relatedMetric: dto.relatedMetric,
                department: dto.department,
                seriesKey: dto.seriesKey,
                calendarEventIdentifier: dto.calendarEventIdentifier,
                isCompleted: dto.isCompleted
            )
            item.id = dto.id
            item.createdDate = dto.createdDate
            modelContext.insert(item)
        }

        for dto in manifest.chatMessages {
            let item = ChatMessage(
                role: dto.role,
                content: dto.content,
                channel: dto.channel,
                threadKey: dto.threadKey
            )
            item.id = dto.id
            item.createdAt = dto.createdAt
            modelContext.insert(item)
        }

        for dto in manifest.workoutPlanPreferences {
            let item = WorkoutPlanPreferences(
                sessionsPerWeek: dto.sessionsPerWeek,
                dietAdviceText: dto.dietAdviceText,
                weeklySummaryText: dto.weeklySummaryText,
                lastGeneratedSource: dto.lastGeneratedSource,
                weekStartDate: dto.weekStartDate,
                weeklyBurnGoalKcal: dto.weeklyBurnGoalKcal,
                excludedExercisesText: dto.excludedExercisesText,
                dailyCalorieTargetKcal: dto.dailyCalorieTargetKcal,
                dailyProteinGrams: dto.dailyProteinGrams,
                dailyCarbGrams: dto.dailyCarbGrams,
                dailyFatGrams: dto.dailyFatGrams,
                nutritionPlanSource: dto.nutritionPlanSource,
                nutritionNotes: dto.nutritionNotes,
                restDayCalorieTargetKcal: dto.restDayCalorieTargetKcal,
                restDayProteinGrams: dto.restDayProteinGrams,
                restDayCarbGrams: dto.restDayCarbGrams,
                restDayFatGrams: dto.restDayFatGrams,
                restDayNotes: dto.restDayNotes,
                planTypeRaw: dto.planTypeRaw,
                planStyleRaw: dto.planStyleRaw,
                inferredFromHealthKit: dto.inferredFromHealthKit,
                healthKitWorkoutSummaryText: dto.healthKitWorkoutSummaryText,
                moodDayOverridesText: dto.moodDayOverridesText,
                moodPinnedWeekdaysText: dto.moodPinnedWeekdaysText
            )
            item.id = dto.id
            item.updatedAt = dto.updatedAt
            modelContext.insert(item)
        }

        for dto in manifest.workoutPlanEntries {
            let item = WorkoutPlanEntry(
                dayOfWeek: dto.dayOfWeek,
                workoutType: dto.workoutType,
                targetMinutes: dto.targetMinutes,
                intensity: dto.intensity,
                cyclePhase: dto.cyclePhase,
                weekStartDate: dto.weekStartDate,
                notes: dto.notes,
                moodReminderText: dto.moodReminderText,
                targetCalories: dto.targetCalories,
                replanNote: dto.replanNote,
                source: dto.source,
                isCompleted: dto.isCompleted,
                completedAt: dto.completedAt
            )
            item.id = dto.id
            item.createdAt = dto.createdAt
            modelContext.insert(item)
        }

        for dto in manifest.workoutExercises {
            let item = WorkoutExercise(
                sessionId: dto.sessionId,
                sortOrder: dto.sortOrder,
                name: dto.name,
                muscleGroup: dto.muscleGroup,
                equipment: dto.equipment,
                sets: dto.sets,
                reps: dto.reps,
                restSeconds: dto.restSeconds,
                targetCalories: dto.targetCalories,
                notes: dto.notes,
                exerciseKind: dto.exerciseKind,
                originalName: dto.originalName,
                swapReason: dto.swapReason
            )
            item.id = dto.id
            item.completedSets = dto.completedSets
            item.isSkipped = dto.isSkipped
            item.createdAt = dto.createdAt
            modelContext.insert(item)
        }
    }

    // MARK: - Mappers

    private static func mapFoodEntry(_ item: FoodEntry) -> HealthDataBackupManifest.FoodEntry {
        .init(
            id: item.id, rawInput: item.rawInput, foodName: item.foodName,
            grams: item.grams, calories: item.calories, protein: item.protein,
            carbohydrates: item.carbohydrates, fat: item.fat,
            createdAt: item.createdAt, mealType: item.mealType
        )
    }

    private static func mapFoodPreference(_ item: FoodPreference) -> HealthDataBackupManifest.FoodPreference {
        .init(
            id: item.id, keyword: item.keyword, defaultDescription: item.defaultDescription,
            createdAt: item.createdAt, usageCount: item.usageCount,
            defaultGrams: item.defaultGrams, defaultCalories: item.defaultCalories,
            defaultProtein: item.defaultProtein, defaultCarbs: item.defaultCarbs, defaultFat: item.defaultFat
        )
    }

    private static func mapUserGoal(_ item: UserGoal) -> HealthDataBackupManifest.UserGoal {
        .init(
            id: item.id, targetWeight: item.targetWeight, targetDate: item.targetDate,
            targetBodyFat: item.targetBodyFat, currentBodyFat: item.currentBodyFat,
            targetLeanBodyMassKg: item.targetLeanBodyMassKg, currentLeanBodyMassKg: item.currentLeanBodyMassKg,
            height: item.height, age: item.age, gender: item.gender, activityLevel: item.activityLevel,
            createdAt: item.createdAt, updatedAt: item.updatedAt
        )
    }

    private static func mapWeightEntry(_ item: WeightEntry) -> HealthDataBackupManifest.WeightEntry {
        .init(id: item.id, weight: item.weight, date: item.date, source: item.source)
    }

    private static func mapUserSettings(_ item: UserSettings) -> HealthDataBackupManifest.UserSettings {
        .init(
            weightUnit: item.weightUnit, appearanceMode: item.appearanceMode,
            profileNickname: item.profileNickname,
            workoutMorningReminderEnabled: item.workoutMorningReminderEnabled,
            workoutMorningReminderHour: item.workoutMorningReminderHour,
            workoutMorningReminderMinute: item.workoutMorningReminderMinute,
            elderModeEnabled: item.elderModeEnabled, createdAt: item.createdAt
        )
    }

    private static func mapCycleProfile(_ item: CycleProfile) -> HealthDataBackupManifest.CycleProfile {
        .init(
            lastPeriodStart: item.lastPeriodStart, averageCycleLength: item.averageCycleLength,
            averagePeriodLength: item.averagePeriodLength, dataSource: item.dataSource,
            lastSyncedAt: item.lastSyncedAt
        )
    }

    private static func mapReport(_ item: Report) -> HealthDataBackupManifest.Report {
        .init(
            id: item.id, fileName: item.fileName, sourceType: item.sourceType,
            importDate: item.importDate, examDate: item.examDate, isVerified: item.isVerified,
            rawOCRText: item.rawOCRText, recommendationsText: item.recommendationsText
        )
    }

    private static func mapHealthMetric(_ item: HealthMetric) -> HealthDataBackupManifest.HealthMetric {
        .init(
            id: item.id, reportId: item.report?.id, name: item.name, value: item.value,
            valueText: item.valueText, unit: item.unit, referenceRange: item.referenceRange,
            isAbnormal: item.isAbnormal, date: item.date, category: item.category,
            reportSection: item.reportSection, severityRank: item.severityRank,
            assessmentNote: item.assessmentNote, morphologyTag: item.morphologyTag,
            organSiteTag: item.organSiteTag
        )
    }

    private static func mapRiskFlag(_ item: RiskFlag) -> HealthDataBackupManifest.RiskFlag {
        .init(
            id: item.id, metricName: item.metricName, severity: item.severity,
            currentValue: item.currentValue, trendDescription: item.trendDescription,
            suggestedAction: item.suggestedAction, checkupMonths: item.checkupMonths,
            department: item.department, seriesKey: item.seriesKey,
            createdDate: item.createdDate, isResolved: item.isResolved
        )
    }

    private static func mapCheckupPlan(_ item: CheckupPlan) -> HealthDataBackupManifest.CheckupPlan {
        .init(
            id: item.id, metricName: item.metricName, department: item.department,
            seriesKey: item.seriesKey, frequencyInMonths: item.frequencyInMonths,
            lastExamDate: item.lastExamDate, nextDueDate: item.nextDueDate,
            reminderDaysBefore: item.reminderDaysBefore
        )
    }

    private static func mapTodoItem(_ item: TodoItem) -> HealthDataBackupManifest.TodoItem {
        .init(
            id: item.id, title: item.title, dueDate: item.dueDate, location: item.location,
            notes: item.notes, source: item.source, relatedMetric: item.relatedMetric,
            department: item.department, seriesKey: item.seriesKey,
            calendarEventIdentifier: item.calendarEventIdentifier,
            isCompleted: item.isCompleted, createdDate: item.createdDate
        )
    }

    private static func mapChatMessage(_ item: ChatMessage) -> HealthDataBackupManifest.ChatMessage {
        .init(
            id: item.id, role: item.role, content: item.content,
            createdAt: item.createdAt, channel: item.channel, threadKey: item.threadKey
        )
    }

    private static func mapWorkoutPlanPreferences(_ item: WorkoutPlanPreferences) -> HealthDataBackupManifest.WorkoutPlanPreferences {
        .init(
            id: item.id, sessionsPerWeek: item.sessionsPerWeek,
            dietAdviceText: item.dietAdviceText, weeklySummaryText: item.weeklySummaryText,
            lastGeneratedSource: item.lastGeneratedSource, weekStartDate: item.weekStartDate,
            weeklyBurnGoalKcal: item.weeklyBurnGoalKcal, excludedExercisesText: item.excludedExercisesText,
            dailyCalorieTargetKcal: item.dailyCalorieTargetKcal, dailyProteinGrams: item.dailyProteinGrams,
            dailyCarbGrams: item.dailyCarbGrams, dailyFatGrams: item.dailyFatGrams,
            nutritionPlanSource: item.nutritionPlanSource, nutritionNotes: item.nutritionNotes,
            restDayCalorieTargetKcal: item.restDayCalorieTargetKcal,
            restDayProteinGrams: item.restDayProteinGrams, restDayCarbGrams: item.restDayCarbGrams,
            restDayFatGrams: item.restDayFatGrams, restDayNotes: item.restDayNotes,
            planTypeRaw: item.planTypeRaw, planStyleRaw: item.planStyleRaw,
            inferredFromHealthKit: item.inferredFromHealthKit,
            healthKitWorkoutSummaryText: item.healthKitWorkoutSummaryText,
            moodDayOverridesText: item.moodDayOverridesText,
            moodPinnedWeekdaysText: item.moodPinnedWeekdaysText, updatedAt: item.updatedAt
        )
    }

    private static func mapWorkoutPlanEntry(_ item: WorkoutPlanEntry) -> HealthDataBackupManifest.WorkoutPlanEntry {
        .init(
            id: item.id, dayOfWeek: item.dayOfWeek, workoutType: item.workoutType,
            targetMinutes: item.targetMinutes, intensity: item.intensity, cyclePhase: item.cyclePhase,
            weekStartDate: item.weekStartDate, notes: item.notes, moodReminderText: item.moodReminderText,
            targetCalories: item.targetCalories, replanNote: item.replanNote, source: item.source,
            isCompleted: item.isCompleted, completedAt: item.completedAt, createdAt: item.createdAt
        )
    }

    private static func mapWorkoutExercise(_ item: WorkoutExercise) -> HealthDataBackupManifest.WorkoutExercise {
        .init(
            id: item.id, sessionId: item.sessionId, sortOrder: item.sortOrder, name: item.name,
            muscleGroup: item.muscleGroup, equipment: item.equipment, sets: item.sets, reps: item.reps,
            restSeconds: item.restSeconds, targetCalories: item.targetCalories, notes: item.notes,
            exerciseKind: item.exerciseKind, originalName: item.originalName, swapReason: item.swapReason,
            completedSets: item.completedSets, isSkipped: item.isSkipped, createdAt: item.createdAt
        )
    }
}
