import Foundation

enum FoodParsingPrompt {
    static let basePrompt = """
营养分析师。解析食物返回JSON数组。

规则：无克重则估算份量。数值保留1位小数。
时间："昨天"=days_ago:1，"前天"=2，默认=0
餐次：识别早餐/午饭/中饭/下午茶/晚饭/夜宵等，填入 meal_type。
meal_type 取值：breakfast | lunch | afternoon_tea | dinner | late_night | snack
若用户未提及餐次，可省略 meal_type。

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

    // Keep backward compatibility
    static var systemPrompt: String {
        basePrompt
    }
}
