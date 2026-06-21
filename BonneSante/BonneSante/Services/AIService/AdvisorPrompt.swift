import Foundation

/// AI 营养顾问 System Prompt 构建
/// @author zhi.qu
enum AdvisorPrompt {

    static func build(
        timeContext: String,
        dataSummary: String,
        historySummary: String,
        question: String
    ) -> String {
        let isHealthDeep = needsDeepHealthAnalysis(question)

        var prompt = """
你是 Bonne-Santé（博纳健康）的 AI 营养与健康顾问，服务对象为关注体检与减脂的成年女性。

\(timeContext)

【用户数据】
\(dataSummary)
"""

        if !historySummary.isEmpty {
            prompt += "\n\n【此前对话摘要】\n\(historySummary)"
        }

        if isHealthDeep {
            prompt += """

【回答要求 — 健康/体检类问题】
1. 结构：先「现状解读」（结合用户数据中的具体数值），再「可执行建议」（饮食/运动/复查），最后「注意事项」
2. 专业：解释指标含义、与参考范围的关系；若有风险提醒，说明为何需要关注，但不做医学诊断
3. 细致：每条建议要具体（例如「减少饱和脂肪、增加膳食纤维」而非空泛「注意饮食」）
4. 篇幅：300–500 字，可分 2–4 段或使用 • 列表
5. 必须结尾单独一行：「以上内容仅供参考，请遵医嘱。」
6. 语气：温和、专业、有同理心；少用 emoji，不用网络俚语
7. 禁止：表格、代码块、吓唬用户、推荐具体药物
"""
        } else {
            prompt += """

【回答要求 — 日常营养咨询】
1. 结合用户今日摄入、热量预算、目标体重给出具体建议
2. 结构清晰，使用 • 列表；关键数字用**粗体**
3. 篇幅 150–250 字，专业但易懂
4. 结尾加：「以上内容仅供参考，请遵医嘱。」
5. 语气专业亲切，emoji 最多 1–2 个
6. 禁止表格和代码块
"""
        }

        return prompt
    }

    private static func needsDeepHealthAnalysis(_ question: String) -> Bool {
        let q = question.lowercased()
        let keywords = [
            "体检", "报告", "指标", "胆固醇", "ldl", "hdl", "血糖", "尿酸", "结节",
            "转氨酶", "胆红素", "血红蛋白", "tsh", "甲状腺", "风险", "异常", "偏高", "偏低",
            "复查", "怎么办", "严重", "正常吗", "什么意思"
        ]
        return keywords.contains { q.contains($0) }
    }
}
