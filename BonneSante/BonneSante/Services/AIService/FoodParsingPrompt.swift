import Foundation

/// 拍照录入模式
enum FoodPhotoInputMode: String, CaseIterable, Identifiable {
    case mealPhoto = "meal"
    case nutritionLabel = "label"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mealPhoto: return "拍食物"
        case .nutritionLabel: return "拍营养表"
        }
    }

    var instruction: String {
        switch self {
        case .mealPhoto:
            return "拍照 + 文字一起用更准：说明食物名称、重量、吃了几分饱"
        case .nutritionLabel:
            return "拍摄包装上的营养成分表，按表内数值录入（可在下方补充吃了多少）"
        }
    }

    var placeholderWithImage: String {
        switch self {
        case .mealPhoto:
            return "例：鸡胸肉约150g、七分饱；或 米饭一碗、五分饱"
        case .nutritionLabel:
            return "例如：吃了1袋（40g）、半包、200ml、一整份"
        }
    }

    var parseButtonTitle: String {
        switch self {
        case .mealPhoto: return "识别食物"
        case .nutritionLabel: return "读取营养表"
        }
    }
}

enum FoodParsingPrompt {
    static let basePrompt = """
营养分析师。解析食物返回JSON数组。

规则：无克重则估算份量。数值保留1位小数。
时间："昨天"=days_ago:1，"前天"=2，默认=0
餐次：识别早餐/午饭/中饭/下午茶/晚饭/夜宵等，填入 meal_type。
meal_type 取值：breakfast | lunch | afternoon_tea | dinner | late_night | snack
若用户未提及餐次，可省略 meal_type。

【照片 + 文字同时提供时】
- 文字描述优先：食物名称、克数/份量、几分饱必须采纳
- 图片用于识别种类与辅助估重
- 几分饱换算（在已有估重基础上缩放 grams 与全部营养素）：
  · 三分饱≈30% · 五分饱≈50% · 七分饱≈70% · 八分饱≈80% · 吃饱/十分≈100%
- notes 中简要说明如何结合图片与文字得出结果

返回格式（必须是数组）：
[{"food_name":"食物名","grams":100,"calories":200,"protein":10,"carbohydrates":20,"fat":5,"days_ago":0,"meal_type":"lunch"}]

多食物示例：
[{"food_name":"米饭","grams":150,"calories":195,"protein":4,"carbohydrates":43,"fat":0.5,"days_ago":0,"meal_type":"lunch"},{"food_name":"鸡蛋","grams":50,"calories":72,"protein":6,"carbohydrates":1,"fat":5,"days_ago":0,"meal_type":"lunch"}]

只返回JSON，无其他文字。
"""

    /// Generate system prompt with user's food preferences
    static func systemPrompt(with preferences: [FoodPreference] = []) -> String {
        var prompt = basePrompt

        // Limit to top 10 most used preferences for faster response
        let topPreferences = Array(preferences.prefix(10))

        if !topPreferences.isEmpty {
            prompt += "\n\n【用户的食物习惯】\n"
            prompt += "当用户提到以下关键词时，使用预设数值：\n"

            for pref in topPreferences {
                prompt += "- \"\(pref.keyword)\" → \(pref.promptDescription)\n"
            }
        }

        return prompt
    }

    /// 拍食物时用户 prompt（图片 + 可选文字）
    static func mealPhotoUserPrompt(additionalContext: String?) -> String {
        var text = "请识别图片中的食物并估算营养。"
        if let context = additionalContext?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            text += """

            【用户文字说明（优先于纯图像估算）】
            \(context)
            请结合图片与用户说明：采纳用户给出的食物名、克数/份量、几分饱；若只有几分饱则在图像估重基础上按比例缩放所有营养素。
            """
        } else {
            text += " 用户未补充文字，请根据图片估算份量。"
        }
        return text
    }

    // Keep backward compatibility
    static var systemPrompt: String {
        basePrompt
    }

    /// 包装营养成分表识读（Qwen VL）
    static let nutritionLabelBasePrompt = """
你是营养标签 OCR 分析师。从食物包装照片读取「营养成分表 / Nutrition Facts」，按标签数值计算摄入量，返回 JSON 数组（通常 1 项）。

【识读规则】
1. 读取产品名称（包装正面或标签附近），填入 food_name
2. 识别基准：每 100g、每 100ml、每份（注明每份克数/毫升数）
3. 能量单位：优先 kcal；若仅 kJ，除以 4.184 转为 kcal
4. 读取蛋白质、脂肪、碳水化合物（或碳水化物），与标签一致，不要估算
5. 根据用户补充份量计算实际摄入：
   - 有明确克数/毫升/「半包」「1袋」→ 按比例换算
   - 无补充且标签有「每份 X g」→ 默认 1 份
   - 无补充且仅「每 100g/ml」→ 默认 100g 或 100ml
6. grams = 实际摄入克数（或毫升数，液体用 ml 数值填入 grams 字段）
7. confidence 固定 "high"；notes 写明「来源：包装营养表」及基准（如「按每份40g×1份」）
8. 若同时有每 100g 与每份，优先用每份再按用户份量缩放

返回格式（必须是数组）：
[{"food_name":"产品名","grams":40,"calories":180,"protein":6,"carbohydrates":22,"fat":7,"confidence":"high","notes":"来源：包装营养表；按每份40g×1份","days_ago":0}]

只返回 JSON，无其他文字。
"""

    static func nutritionLabelSystemPrompt(with preferences: [FoodPreference] = []) -> String {
        var prompt = nutritionLabelBasePrompt
        let topPreferences = Array(preferences.prefix(10))
        if !topPreferences.isEmpty {
            prompt += "\n\n【用户习惯关键词】若产品名含关键词，份量仍按标签与用户说明计算。\n"
            for pref in topPreferences {
                prompt += "- \"\(pref.keyword)\" → \(pref.promptDescription)\n"
            }
        }
        return prompt
    }

    static func nutritionLabelUserPrompt(additionalContext: String?) -> String {
        var text = "请读取图片中包装上的营养成分表，并按标签数值返回 JSON。"
        if let context = additionalContext?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            text += "\n【用户实际食用份量】\(context)"
        } else {
            text += "\n【用户未说明份量】按标签「每份」或 100g/100ml 默认一份计算。"
        }
        return text
    }
}
