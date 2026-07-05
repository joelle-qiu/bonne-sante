import Foundation

/// Bonne-Santé 全量本地数据备份 JSON 结构（v2 起含 API Key）
/// @author jiali.qiu
enum HealthDataBackupManifest {
    static let formatVersion = 2
    static let minimumFormatVersion = 1
    static let currentSchemaVersion = SwiftDataContainerFactory.schemaVersion
    static let fileExtension = "json"
    static let suggestedFilenamePrefix = "bonnesante-backup"

    struct File: Codable {
        var formatVersion: Int
        var exportedAt: Date
        var appSchemaVersion: Int
        var foodEntries: [FoodEntry]
        var foodPreferences: [FoodPreference]
        var userGoals: [UserGoal]
        var weightEntries: [WeightEntry]
        var userSettings: [UserSettings]
        var cycleProfiles: [CycleProfile]
        var reports: [Report]
        var healthMetrics: [HealthMetric]
        var riskFlags: [RiskFlag]
        var checkupPlans: [CheckupPlan]
        var todoItems: [TodoItem]
        var chatMessages: [ChatMessage]
        var workoutPlanPreferences: [WorkoutPlanPreferences]
        var workoutPlanEntries: [WorkoutPlanEntry]
        var workoutExercises: [WorkoutExercise]
        /// v2：Keychain 中的用户 API Key 与 AI 偏好（可选，v1 备份无此字段）
        var appSecrets: AppSecrets?

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
            case exportedAt = "exported_at"
            case appSchemaVersion = "app_schema_version"
            case foodEntries = "food_entries"
            case foodPreferences = "food_preferences"
            case userGoals = "user_goals"
            case weightEntries = "weight_entries"
            case userSettings = "user_settings"
            case cycleProfiles = "cycle_profiles"
            case reports
            case healthMetrics = "health_metrics"
            case riskFlags = "risk_flags"
            case checkupPlans = "checkup_plans"
            case todoItems = "todo_items"
            case chatMessages = "chat_messages"
            case workoutPlanPreferences = "workout_plan_preferences"
            case workoutPlanEntries = "workout_plan_entries"
            case workoutExercises = "workout_exercises"
            case appSecrets = "app_secrets"
        }
    }

    /// 用户 API Key 与 AI 相关偏好（明文 JSON，请妥善保管备份文件）
    struct AppSecrets: Codable {
        var deepSeekAPIKey: String?
        var qwenAPIKey: String?
        var apiRegion: String?
        var reportAIAssistEnabled: Bool?

        enum CodingKeys: String, CodingKey {
            case deepSeekAPIKey = "deepseek_api_key"
            case qwenAPIKey = "qwen_api_key"
            case apiRegion = "api_region"
            case reportAIAssistEnabled = "report_ai_assist_enabled"
        }

        var includesAPIKeys: Bool {
            let deep = deepSeekAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let qwen = qwenAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !deep.isEmpty || !qwen.isEmpty
        }
    }

    struct FoodEntry: Codable {
        var id: UUID
        var rawInput: String
        var foodName: String
        var grams: Double
        var calories: Double
        var protein: Double
        var carbohydrates: Double
        var fat: Double
        var createdAt: Date
        var mealType: String

        enum CodingKeys: String, CodingKey {
            case id
            case rawInput = "raw_input"
            case foodName = "food_name"
            case grams, calories, protein, carbohydrates, fat
            case createdAt = "created_at"
            case mealType = "meal_type"
        }
    }

    struct FoodPreference: Codable {
        var id: UUID
        var keyword: String
        var defaultDescription: String
        var createdAt: Date
        var usageCount: Int
        var defaultGrams: Double?
        var defaultCalories: Double?
        var defaultProtein: Double?
        var defaultCarbs: Double?
        var defaultFat: Double?

        enum CodingKeys: String, CodingKey {
            case id, keyword
            case defaultDescription = "default_description"
            case createdAt = "created_at"
            case usageCount = "usage_count"
            case defaultGrams = "default_grams"
            case defaultCalories = "default_calories"
            case defaultProtein = "default_protein"
            case defaultCarbs = "default_carbs"
            case defaultFat = "default_fat"
        }
    }

    struct UserGoal: Codable {
        var id: UUID
        var targetWeight: Double
        var targetDate: Date?
        var targetBodyFat: Double?
        var currentBodyFat: Double?
        var targetLeanBodyMassKg: Double?
        var currentLeanBodyMassKg: Double?
        var height: Double
        var age: Int
        var gender: String
        var activityLevel: String
        var createdAt: Date
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case targetWeight = "target_weight"
            case targetDate = "target_date"
            case targetBodyFat = "target_body_fat"
            case currentBodyFat = "current_body_fat"
            case targetLeanBodyMassKg = "target_lean_body_mass_kg"
            case currentLeanBodyMassKg = "current_lean_body_mass_kg"
            case height, age, gender
            case activityLevel = "activity_level"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    struct WeightEntry: Codable {
        var id: UUID
        var weight: Double
        var date: Date
        var source: String
    }

    struct UserSettings: Codable {
        var weightUnit: String
        var appearanceMode: String
        var profileNickname: String
        var workoutMorningReminderEnabled: Bool
        var workoutMorningReminderHour: Int
        var workoutMorningReminderMinute: Int
        var elderModeEnabled: Bool
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case weightUnit = "weight_unit"
            case appearanceMode = "appearance_mode"
            case profileNickname = "profile_nickname"
            case workoutMorningReminderEnabled = "workout_morning_reminder_enabled"
            case workoutMorningReminderHour = "workout_morning_reminder_hour"
            case workoutMorningReminderMinute = "workout_morning_reminder_minute"
            case elderModeEnabled = "elder_mode_enabled"
            case createdAt = "created_at"
        }
    }

    struct CycleProfile: Codable {
        var lastPeriodStart: Date
        var averageCycleLength: Int
        var averagePeriodLength: Int
        var dataSource: String
        var lastSyncedAt: Date?

        enum CodingKeys: String, CodingKey {
            case lastPeriodStart = "last_period_start"
            case averageCycleLength = "average_cycle_length"
            case averagePeriodLength = "average_period_length"
            case dataSource = "data_source"
            case lastSyncedAt = "last_synced_at"
        }
    }

    struct Report: Codable {
        var id: UUID
        var fileName: String
        var sourceType: String
        var importDate: Date
        var examDate: Date?
        var isVerified: Bool
        var rawOCRText: String
        var recommendationsText: String

        enum CodingKeys: String, CodingKey {
            case id
            case fileName = "file_name"
            case sourceType = "source_type"
            case importDate = "import_date"
            case examDate = "exam_date"
            case isVerified = "is_verified"
            case rawOCRText = "raw_ocr_text"
            case recommendationsText = "recommendations_text"
        }
    }

    struct HealthMetric: Codable {
        var id: UUID
        var reportId: UUID?
        var name: String
        var value: Double
        var valueText: String
        var unit: String
        var referenceRange: String
        var isAbnormal: Bool
        var date: Date
        var category: String
        var reportSection: String
        var severityRank: Int
        var assessmentNote: String
        var morphologyTag: String
        var organSiteTag: String

        enum CodingKeys: String, CodingKey {
            case id
            case reportId = "report_id"
            case name, value
            case valueText = "value_text"
            case unit
            case referenceRange = "reference_range"
            case isAbnormal = "is_abnormal"
            case date, category
            case reportSection = "report_section"
            case severityRank = "severity_rank"
            case assessmentNote = "assessment_note"
            case morphologyTag = "morphology_tag"
            case organSiteTag = "organ_site_tag"
        }
    }

    struct RiskFlag: Codable {
        var id: UUID
        var metricName: String
        var severity: String
        var currentValue: String
        var trendDescription: String
        var suggestedAction: String
        var checkupMonths: Int
        var department: String
        var seriesKey: String
        var createdDate: Date
        var isResolved: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case metricName = "metric_name"
            case severity
            case currentValue = "current_value"
            case trendDescription = "trend_description"
            case suggestedAction = "suggested_action"
            case checkupMonths = "checkup_months"
            case department
            case seriesKey = "series_key"
            case createdDate = "created_date"
            case isResolved = "is_resolved"
        }
    }

    struct CheckupPlan: Codable {
        var id: UUID
        var metricName: String
        var department: String
        var seriesKey: String
        var frequencyInMonths: Int
        var lastExamDate: Date
        var nextDueDate: Date
        var reminderDaysBefore: [Int]

        enum CodingKeys: String, CodingKey {
            case id
            case metricName = "metric_name"
            case department
            case seriesKey = "series_key"
            case frequencyInMonths = "frequency_in_months"
            case lastExamDate = "last_exam_date"
            case nextDueDate = "next_due_date"
            case reminderDaysBefore = "reminder_days_before"
        }
    }

    struct TodoItem: Codable {
        var id: UUID
        var title: String
        var dueDate: Date
        var location: String?
        var notes: String?
        var source: String
        var relatedMetric: String?
        var department: String
        var seriesKey: String
        var calendarEventIdentifier: String
        var isCompleted: Bool
        var createdDate: Date

        enum CodingKeys: String, CodingKey {
            case id, title
            case dueDate = "due_date"
            case location, notes, source
            case relatedMetric = "related_metric"
            case department
            case seriesKey = "series_key"
            case calendarEventIdentifier = "calendar_event_identifier"
            case isCompleted = "is_completed"
            case createdDate = "created_date"
        }
    }

    struct ChatMessage: Codable {
        var id: UUID
        var role: String
        var content: String
        var createdAt: Date
        var channel: String
        var threadKey: String

        enum CodingKeys: String, CodingKey {
            case id, role, content
            case createdAt = "created_at"
            case channel
            case threadKey = "thread_key"
        }
    }

    struct WorkoutPlanPreferences: Codable {
        var id: UUID
        var sessionsPerWeek: Int
        var dietAdviceText: String
        var weeklySummaryText: String
        var lastGeneratedSource: String
        var weekStartDate: Date?
        var weeklyBurnGoalKcal: Double
        var excludedExercisesText: String
        var dailyCalorieTargetKcal: Double
        var dailyProteinGrams: Double
        var dailyCarbGrams: Double
        var dailyFatGrams: Double
        var nutritionPlanSource: String
        var nutritionNotes: String
        var restDayCalorieTargetKcal: Double
        var restDayProteinGrams: Double
        var restDayCarbGrams: Double
        var restDayFatGrams: Double
        var restDayNotes: String
        var planTypeRaw: String
        var planStyleRaw: String
        var inferredFromHealthKit: Bool
        var healthKitWorkoutSummaryText: String
        var moodDayOverridesText: String
        var moodPinnedWeekdaysText: String
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case sessionsPerWeek = "sessions_per_week"
            case dietAdviceText = "diet_advice_text"
            case weeklySummaryText = "weekly_summary_text"
            case lastGeneratedSource = "last_generated_source"
            case weekStartDate = "week_start_date"
            case weeklyBurnGoalKcal = "weekly_burn_goal_kcal"
            case excludedExercisesText = "excluded_exercises_text"
            case dailyCalorieTargetKcal = "daily_calorie_target_kcal"
            case dailyProteinGrams = "daily_protein_grams"
            case dailyCarbGrams = "daily_carb_grams"
            case dailyFatGrams = "daily_fat_grams"
            case nutritionPlanSource = "nutrition_plan_source"
            case nutritionNotes = "nutrition_notes"
            case restDayCalorieTargetKcal = "rest_day_calorie_target_kcal"
            case restDayProteinGrams = "rest_day_protein_grams"
            case restDayCarbGrams = "rest_day_carb_grams"
            case restDayFatGrams = "rest_day_fat_grams"
            case restDayNotes = "rest_day_notes"
            case planTypeRaw = "plan_type_raw"
            case planStyleRaw = "plan_style_raw"
            case inferredFromHealthKit = "inferred_from_health_kit"
            case healthKitWorkoutSummaryText = "health_kit_workout_summary_text"
            case moodDayOverridesText = "mood_day_overrides_text"
            case moodPinnedWeekdaysText = "mood_pinned_weekdays_text"
            case updatedAt = "updated_at"
        }
    }

    struct WorkoutPlanEntry: Codable {
        var id: UUID
        var dayOfWeek: Int
        var workoutType: String
        var targetMinutes: Int
        var intensity: String
        var cyclePhase: String
        var weekStartDate: Date
        var notes: String
        var moodReminderText: String
        var targetCalories: Double
        var replanNote: String
        var source: String
        var isCompleted: Bool
        var completedAt: Date?
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case dayOfWeek = "day_of_week"
            case workoutType = "workout_type"
            case targetMinutes = "target_minutes"
            case intensity
            case cyclePhase = "cycle_phase"
            case weekStartDate = "week_start_date"
            case notes
            case moodReminderText = "mood_reminder_text"
            case targetCalories = "target_calories"
            case replanNote = "replan_note"
            case source
            case isCompleted = "is_completed"
            case completedAt = "completed_at"
            case createdAt = "created_at"
        }
    }

    struct WorkoutExercise: Codable {
        var id: UUID
        var sessionId: UUID
        var sortOrder: Int
        var name: String
        var muscleGroup: String
        var equipment: String
        var sets: Int
        var reps: String
        var restSeconds: Int
        var targetCalories: Double
        var notes: String
        var exerciseKind: String
        var originalName: String
        var swapReason: String
        var completedSets: Int
        var isSkipped: Bool
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case sessionId = "session_id"
            case sortOrder = "sort_order"
            case name
            case muscleGroup = "muscle_group"
            case equipment, sets, reps
            case restSeconds = "rest_seconds"
            case targetCalories = "target_calories"
            case notes
            case exerciseKind = "exercise_kind"
            case originalName = "original_name"
            case swapReason = "swap_reason"
            case completedSets = "completed_sets"
            case isSkipped = "is_skipped"
            case createdAt = "created_at"
        }
    }

    /// 导入摘要（设置页展示）
    struct ImportSummary {
        let foodEntryCount: Int
        let reportCount: Int
        let workoutSessionCount: Int
        var includesAppSecrets: Bool = false
        var keysRestored: Bool = false

        var previewLabel: String {
            var parts = [
                "饮食 \(foodEntryCount) 条",
                "报告 \(reportCount) 份",
                "训练 \(workoutSessionCount) 场"
            ]
            if includesAppSecrets {
                parts.append("含 API Key 配置")
            }
            return parts.joined(separator: " · ")
        }

        var successLabel: String {
            var label = previewLabel
            if keysRestored {
                label += " · 已写入 Keychain"
            }
            return label
        }

        /// 兼容旧调用
        var label: String { previewLabel }
    }
}
