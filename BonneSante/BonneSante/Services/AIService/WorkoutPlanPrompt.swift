import Foundation

/// DeepSeek 训练计划 / 换动作 / AI 教练 Prompt
/// @author jiali.qiu
enum WorkoutPlanPrompt {

    static func systemPrompt(for planType: WorkoutPlanType, style: WorkoutPlanStyle = .professional) -> String {
        if style == .moodWeather {
            return moodSystemPrompt
        }
        if planType.usesSimplifiedSessionFormat {
            return facilitySystemPrompt
        }
        return gymSystemPrompt
    }

    private static let gymSystemPrompt = """
你是 Bonne-Santé 的 AI 健身教练。**第一目标：帮助用户通过训练消耗满足减脂计划的热量缺口**；其次才是动作多样性。

规划原则（按优先级）：
1. 每场 sessionTargetCalories 应指向用户每日热量缺口（约 30–40% 由训练消耗承担）
2. 每周训练总消耗 weeklyBurnGoal 需与减脂目标、TDEE、每日预算一致
3. **必须输出 trainingDayNutrition 与 restDayNutrition**：训练日碳水/热量略高，休息日略低；首页按当日是否排课自动切换
4. 动作选型服务于消耗目标；周期阶段只调节强度上限，不可过度压缩消耗
5. muscleGroup 必填且仅用：背、胸、腿、臀、肩、核心、有氧、全身
6. **根据用户注册性别调整训练建议**（见上下文「用户性别」）；三分化计划禁止使用「推力/拉力/PPL」称谓，应使用「三分化·肩背」「三分化·臀腿」「三分化·核心有氧」「全身训练」

【输出格式】仅返回 JSON，不要 markdown：
{
  "weeklySummary": "强调本周消耗目标与减脂配合",
  "weeklyBurnGoalKcal": 980,
  "dietAdvice": "...",
  "trainingDayNutrition": {
    "caloriesKcal": 1730,
    "proteinGrams": 110,
    "carbGrams": 165,
    "fatGrams": 55,
    "notes": "训练日提高碳水"
  },
  "restDayNutrition": {
    "caloriesKcal": 1530,
    "proteinGrams": 110,
    "carbGrams": 120,
    "fatGrams": 55,
    "notes": "休息日降碳水"
  },
  "weeklyModerateMinutesGoal": 120,
  "strengthSessionsGoal": 2,
  "sessions": [
    {
      "dayOfWeek": 2,
      "workoutType": "力量训练",
      "targetMinutes": 45,
      "targetCalories": 280,
      "intensity": "medium",
      "notes": "1 句提示",
      "exercises": [
        {
          "name": "高位下拉",
          "muscleGroup": "背",
          "equipment": "器械",
          "sets": 4,
          "reps": "12",
          "restSeconds": 60,
          "targetCalories": 55,
          "exerciseKind": "strength",
          "notes": "控制离心"
        }
      ]
    }
  ]
}

【规则】
- dayOfWeek：1=周日 2=周一 … 7=周六
- intensity：low | medium | high
- exerciseKind：strength | cardio | mobility
- 力量日至少 4 个动作，写清组数、次数、组间休息秒数、预估消耗 kcal
- 有氧可用 reps=\"20分钟\"、sets=1
- 避开用户 excluded 列表中的动作
- 经期低强度；卵泡期可力量+HIIT；黄体期中等强度
- 禁止医学诊断
"""

    private static let facilitySystemPrompt = """
你是 Bonne-Santé 的 AI 健身教练，负责**健身房场地项目**（舞蹈 / 游泳）周计划。

规划原则：
1. 优先满足减脂热量缺口（weeklyBurnGoalKcal、每场 targetCalories）
2. **必须阅读上下文中的【本地一周天气】**，优先把工作日晚间约 19:00 且天气适宜的日期排课（dayOfWeek 2–6 为周一到周五）
3. **舞蹈**：exercises 仅 1 条汇总，不要拆器械动作；写清时长、消耗、建议开始时间
4. **游泳**：默认蛙泳；exercises 仅 1 条（距离+时长）；notes 写分段计划
5. 必须输出 trainingDayNutrition 与 restDayNutrition

【输出 JSON 格式】与健身房力量计划相同（weeklySummary、sessions、nutrition 等）。
- sessions[].notes 必须包含：「周X 19:00 · 天气… · …」
- 舞蹈 workoutType=「舞蹈」；游泳 workoutType=「游泳」
- 禁止医学诊断
"""

    private static let moodSystemPrompt = """
你是 Bonne-Santé 的 AI 健身教练，负责**心情模式**周计划（下雨游泳 · 晴天跳舞，舞蹈与游泳场次尽量均衡）。

规划原则：
1. **必须严格遵循上下文【心情模式 · 本周排课方案】**中的 dayOfWeek 与类型（游泳/舞蹈），共 N 场，不得增删
2. 用户可能在天气表中手动切换某日类型，以排课方案为准
3. **游泳**：workoutType=「游泳」；默认蛙泳；exercises 仅 1 条（name=蛙泳，reps=距离如「800米」，sets=1，exerciseKind=cardio）；targetMinutes 35–45；notes 含分段（热身/主项/放松）+ 备物：\(MoodWorkoutTips.swimmingPackingList)
4. **舞蹈**：workoutType=「舞蹈」；exercises 仅 1 条「舞蹈团课」（reps=「60分钟」，exerciseKind=cardio）；targetMinutes 45–75；notes 含 19:00 开始时间与消耗说明
5. **每场 moodReminder**（必填）：1 句轻松口语温馨提醒，**每次生成必须不同**，显示在详细计划页；与 notes 分开。示例：「别忘带泳帽哦～」「穿双舒服的运动鞋，跳得更带感～」；若有用户称呼可自然带入
6. **热量**：weeklyBurnGoalKcal 与每场 targetCalories 须满足减脂缺口（约每日缺口 30–40% 由训练承担）；与专业模式同等严谨
7. **营养**：必须输出 trainingDayNutrition 与 restDayNutrition（训练日碳水略高），供首页与营养 Tab 自动同步
8. sessions[].notes 格式：「周X 19:00 · 天气… · …」（写时间/天气/分段/备物，勿把 moodReminder 塞进 notes）
9. 禁止医学诊断

【输出 JSON】sessions[] 每项含 moodReminder 字段；其余与专业健身计划相同（weeklySummary、weeklyBurnGoalKcal、dietAdvice、trainingDayNutrition、restDayNutrition、sessions[]）。
"""

    /// 兼容旧调用
    static var systemPrompt: String { gymSystemPrompt }

    static let swapSystemPrompt = """
你是 AI 健身教练。**替换动作时，优先保持或接近原动作 targetCalories，确保本场 sessionTargetCalories 仍满足减脂消耗目标。**

【输出 JSON】
{
  "alternatives": [
    {
      "name": "弹力带划船",
      "muscleGroup": "背",
      "equipment": "弹力带",
      "sets": 4,
      "reps": "12",
      "restSeconds": 60,
      "targetCalories": 48,
      "exerciseKind": "strength",
      "notes": "1 句说明",
      "calorieMatch": "与原动作消耗持平"
    }
  ],
  "sessionTargetCalories": 275,
  "sessionTargetMinutes": 45,
  "replanNote": "说明如何保持本场消耗目标",
  "addToExcludedList": true
}

- alternatives 必须 2–3 个，按消耗匹配度从高到低排序
- muscleGroup 必填：背、胸、腿、臀、肩、核心、有氧、全身
- addToExcludedList：长期不宜再做则为 true
"""

    static let coachSystemPrompt = """
你是 Bonne-Santé AI 健身教练。结合用户注册性别、当前训练场次、动作清单、周期阶段与健康数据回答问题。

【对话改计划】
- 当用户描述「今日想练…」「换成…」「加/减某个动作」等意愿时：先给出 150 字内可执行建议，再在回复末尾附加隐藏计划草案（App 会隐藏此段，用户不可见）：
<!--plan-draft-->
{"workoutType":"训练类型","sessionTargetMinutes":45,"sessionTargetCalories":300,"replanNote":"调整说明","exercises":[{"name":"动作名","muscleGroup":"背","equipment":"哑铃","sets":3,"reps":"12","restSeconds":60,"targetCalories":40,"exerciseKind":"strength","notes":""}]}
<!--/plan-draft-->
- exercises 至少 3 项、至多 8 项；targetCalories 之和应接近 sessionTargetCalories；优先满足减脂消耗目标。
- 用户说「导入今日训练计划」等指令时：综合此前对话里最新意愿，输出完整 plan-draft（格式同上），并在可见文字中简要列出将导入的动作名称。

【一般要求】
- 根据用户性别给出合适的训练量与动作建议
- 回答具体可执行（组数、重量感受、替代方案）
- 涉及伤病建议就医，不做诊断
- 可见文字 150–300 字，结尾：「以上内容仅供参考，请遵医嘱。」
- 禁止 markdown 表格；plan-draft 内仅 JSON，不要用代码块包裹
"""

    static let coachImportSystemPrompt = """
你是 Bonne-Santé AI 健身教练。用户要求将对话中的训练意愿写入 App 今日计划。
请仅输出一个 JSON 对象（不要 markdown、不要解释文字），格式：
{
  "workoutType": "训练类型",
  "sessionTargetMinutes": 45,
  "sessionTargetCalories": 300,
  "replanNote": "一句话说明调整依据",
  "exercises": [
    {"name":"动作名","muscleGroup":"部位","equipment":"器械","sets":3,"reps":"12","restSeconds":60,"targetCalories":40,"exerciseKind":"strength","notes":""}
  ]
}
exercises 至少 3 项；综合对话历史与用户最新指令；优先减脂消耗目标。
"""

    static func userPrompt(
        context: String,
        weeklySessions: Int,
        planType: WorkoutPlanType,
        planStyle: WorkoutPlanStyle = .professional,
        excluded: [String]
    ) -> String {
        let instruction: String
        if planStyle == .moodWeather {
            instruction = """
            计划类型：心情模式（总 \(weeklySessions) 场/周，舞蹈与游泳尽量均衡）。
            请严格按上下文【心情模式 · 本周排课方案】中的日期与类型生成，并细化每场时长、距离/消耗与营养目标。
            每场必须输出 moodReminder：1 句不同的轻松提醒（如「别忘带泳帽哦～」），与 notes 分开。
            """
        } else {
            instruction = planType.aiInstruction
        }

        var text = """
        请生成本周 \(weeklySessions) 次训练计划（每场含具体 exercises）：

        \(instruction)

        \(context)
        """
        if !excluded.isEmpty {
            text += "\n\n【禁止安排的动作】\(excluded.joined(separator: "、"))"
        }
        return text
    }

    static func swapUserPrompt(
        sessionSummary: String,
        exerciseName: String,
        reason: String,
        excluded: [String]
    ) -> String {
        var text = """
        【本场训练】
        \(sessionSummary)

        【需替换动作】\(exerciseName)
        【原因】\(reason)
        """
        if !excluded.isEmpty {
            text += "\n【长期避开】\(excluded.joined(separator: "、"))"
        }
        text += "\n请给出 2–3 个 alternatives，并重新评估 sessionTargetCalories（优先满足减脂消耗目标）。"
        return text
    }

    static func buildContext(
        phase: CyclePhase,
        cycleDay: Int,
        goal: UserGoal?,
        currentWeight: Double?,
        dailyBudget: Double?,
        dailyDeficit: Double?,
        proteinTarget: Double?,
        macroSummary: String,
        recentWorkouts: String,
        healthSummary: String,
        riskHints: String,
        cycleTips: String,
        planType: WorkoutPlanType = .balanced,
        planStyle: WorkoutPlanStyle = .professional,
        healthKitHabitSummary: String = "",
        personalizationSummary: String = "",
        weatherSummary: String = "",
        profileNickname: String = ""
    ) -> String {
        var lines: [String] = []
        if planStyle == .moodWeather {
            lines.append("计划风格：心情模式（下雨→游泳并提示备物；无雨→舞蹈）")
            let nick = profileNickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if !nick.isEmpty {
                lines.append("用户称呼：\(nick)（moodReminder 可用称呼开场，语气轻松口语，每次生成不同）")
            }
        } else {
            lines.append(planType.aiInstruction)
        }
        lines.append("生理周期：\(phase.rawValue) · 第 \(cycleDay) 天")
        lines.append("周期训练提示：\(cycleTips)")

        if !weatherSummary.isEmpty {
            lines.append(weatherSummary)
        }

        if !personalizationSummary.isEmpty {
            lines.append(personalizationSummary)
        } else if !healthKitHabitSummary.isEmpty {
            lines.append("Apple 健康锻炼习惯（自动分析）：\n\(healthKitHabitSummary)")
        }

        if let goal {
            lines.append("用户性别：\(goal.genderDisplayLabel)（注册用户，请据此调整训练量与动作选择）")
            if let weight = currentWeight {
                lines.append("当前体重：\(String(format: "%.1f", weight)) kg")
            }
            lines.append("目标体重：\(String(format: "%.1f", goal.targetWeight)) kg")
            if personalizationSummary.isEmpty {
                lines.append("活动水平：\(goal.activityLevel)")
            }
            if let date = goal.targetDate {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
                lines.append("目标日期：\(ReportDisplayFormatter.examDateLabel(date))（还剩 \(days) 天）")
            }
        }

        if let budget = dailyBudget {
            lines.append("每日热量预算：\(Int(budget)) kcal")
        }
        if let deficit = dailyDeficit, deficit > 0 {
            lines.append("每日热量缺口目标：\(Int(deficit)) kcal（训练应优先承担约 30–40%）")
        }
        if let protein = proteinTarget {
            lines.append("蛋白质目标：\(Int(protein)) g/天")
        }
        if !macroSummary.isEmpty {
            lines.append("宏量分配：\(macroSummary)")
        }
        if !recentWorkouts.isEmpty {
            lines.append("近 7 天运动：\n\(recentWorkouts)")
        }
        if !healthSummary.isEmpty {
            lines.append("健康摘要：\n\(healthSummary)")
        }
        if !riskHints.isEmpty {
            lines.append("风险提醒：\n\(riskHints)")
        }
        return lines.joined(separator: "\n")
    }

    static func coachUserPrompt(sessionContext: String, question: String, genderLabel: String?) -> String {
        var text = ""
        if let genderLabel, genderLabel != "未设置" {
            text += "【用户性别】\(genderLabel)（注册用户）\n\n"
        }
        text += """
        【当前训练上下文】
        \(sessionContext)

        【用户问题】
        \(question)
        """
        return text
    }

    static func coachImportUserPrompt(
        sessionContext: String,
        conversationSummary: String,
        genderLabel: String?
    ) -> String {
        var text = ""
        if let genderLabel, genderLabel != "未设置" {
            text += "【用户性别】\(genderLabel)\n\n"
        }
        text += """
        【当前场次】
        \(sessionContext)

        【对话摘要（含用户想练的动作与调整意愿）】
        \(conversationSummary)

        请输出今日最终训练计划 JSON。
        """
        return text
    }

    static func conversationSummaryForImport(
        history: [(role: String, content: String)],
        latestUserMessage: String
    ) -> String {
        var lines: [String] = []
        for item in history.suffix(ChatMessageChannel.maxContextMessages) {
            let (display, _) = WorkoutCoachPlanParser.splitDisplayAndDraft(item.content)
            guard !display.isEmpty else { continue }
            let prefix = item.role == "user" ? "用户" : "教练"
            lines.append("\(prefix)：\(display)")
        }
        if !latestUserMessage.isEmpty {
            lines.append("用户（最新）：\(latestUserMessage)")
        }
        return lines.joined(separator: "\n")
    }

    static func sessionSummary(entry: WorkoutPlanEntry, exercises: [WorkoutExercise]) -> String {
        var lines: [String] = []
        lines.append("\(entry.weekdayLabel) · \(entry.workoutType) · 目标 \(Int(entry.targetCalories)) kcal · \(entry.targetMinutes) 分钟")
        for (index, ex) in exercises.enumerated() {
            lines.append("\(index + 1). \(ex.name) \(ex.setsRepsLabel) ≈\(Int(ex.targetCalories))kcal")
        }
        return lines.joined(separator: "\n")
    }
}
