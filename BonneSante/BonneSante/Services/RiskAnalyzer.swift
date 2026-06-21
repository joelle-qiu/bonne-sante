import Foundation

/// 体检指标趋势
/// @author jiali.qiu
enum MetricTrend: String {
    case improving = "↓ 改善"
    case worsening = "↑ 恶化"
    case stable = "→ 持平"
    case unknown = "—"
}

/// 10 条初始风险规则（提醒性质，非诊断）
/// @author jiali.qiu
enum RiskAnalyzer {

    struct MetricSnapshot {
        let name: String
        let value: Double
        let valueText: String
        let unit: String
        let date: Date
        let isAbnormal: Bool
        var severityRank: Int = 0
        var assessmentNote: String = ""
    }

    struct RuleMatch {
        let metricName: String
        let severity: RiskSeverity
        let currentValue: String
        let trend: MetricTrend
        let suggestedAction: String
        let todoTitle: String
        let checkupMonths: Int?
        /// 与异常指标摘要一致的科室
        var department: String = ""
        /// 与 HealthProfileEngine 异常项 dedupe key 对齐
        var seriesKey: String = ""
    }

    static func analyze(allMetrics: [MetricSnapshot]) -> [RuleMatch] {
        ClinicalRiskEngine.analyze(snapshots: allMetrics)
    }

    static func analyze(metrics: [HealthMetric]) -> [RuleMatch] {
        ClinicalRiskEngine.analyze(metrics: metrics)
    }

    // MARK: - Rules

    private static func matchRule(for latest: MetricSnapshot, history: [MetricSnapshot]) -> RuleMatch? {
        if shouldSuppressRisk(latest: latest, history: history) {
            return nil
        }

        let key = normalize(latest.name)
        let historyTrend = trend(history)

        func match(
            metricName: String,
            severity: RiskSeverity,
            currentValue: String,
            suggestedAction: String,
            todoTitle: String,
            checkupMonths: Int?
        ) -> RuleMatch {
            RuleMatch(
                metricName: metricName,
                severity: adjustedSeverity(severity, history: history, latest: latest),
                currentValue: currentValue,
                trend: historyTrend,
                suggestedAction: adjustedAction(suggestedAction, history: history),
                todoTitle: todoTitle,
                checkupMonths: checkupMonths
            )
        }

        if key.contains("肺结节") || (key.contains("结节") && key.contains("肺")) {
            if latest.value >= 5 || historyTrend == .worsening {
                return match(
                    metricName: latest.name,
                    severity: .high,
                    currentValue: latest.valueText,
                    suggestedAction: "建议年度胸部 CT 复查",
                    todoTitle: "年度胸部 CT 复查",
                    checkupMonths: 12
                )
            }
        }

        if key.contains("低密度脂蛋白") || key.contains("ldl") {
            if latest.isAbnormal || latest.value > 3.4 || isConsecutiveHigh(history, threshold: 3.4) {
                return match(
                    metricName: latest.name,
                    severity: .medium,
                    currentValue: latest.valueText,
                    suggestedAction: "建议 3–6 月复查血脂，低脂饮食",
                    todoTitle: "复查血脂（LDL）",
                    checkupMonths: 6
                )
            }
        }

        if key.contains("总胆固醇") {
            if latest.isAbnormal || latest.value > 5.2 {
                return match(
                    metricName: latest.name,
                    severity: .medium,
                    currentValue: latest.valueText,
                    suggestedAction: "建议 3–6 月复查血脂",
                    todoTitle: "复查血脂（总胆固醇）",
                    checkupMonths: 6
                )
            }
        }

        if key.contains("乳酸脱氢酶") || key.contains("ldh") {
            if latest.isAbnormal || latest.value < 120 {
                return match(
                    metricName: latest.name,
                    severity: .low,
                    currentValue: latest.valueText,
                    suggestedAction: "建议 1–3 月复查 LDH，并关注有无肌肉损伤或溶血",
                    todoTitle: "复查 LDH",
                    checkupMonths: 3
                )
            }
        }

        if key.contains("脓细胞") {
            if latest.isAbnormal || latest.value > 5 {
                return match(
                    metricName: latest.name,
                    severity: .medium,
                    currentValue: latest.valueText,
                    suggestedAction: "建议妇科门诊就诊",
                    todoTitle: "妇科就诊（阴道分泌物）",
                    checkupMonths: 1
                )
            }
        }

        if key.contains("小叶增生") || (key.contains("乳腺") && latest.valueText.contains("增生")) {
            return match(
                metricName: latest.name,
                severity: .low,
                currentValue: latest.valueText,
                suggestedAction: "建议定期自查，必要时乳腺外科随访",
                todoTitle: "乳腺随访（小叶增生）",
                checkupMonths: 12
            )
        }

        if key.contains("空腹血糖") || key.contains("血糖") {
            if latest.value >= 6.1 {
                return match(
                    metricName: latest.name,
                    severity: .medium,
                    currentValue: latest.valueText,
                    suggestedAction: "建议内分泌科进一步评估",
                    todoTitle: "内分泌科就诊（血糖）",
                    checkupMonths: 3
                )
            }
        }

        if key.contains("tsh") || key.contains("促甲状腺") {
            if latest.isAbnormal || latest.value < 0.27 || latest.value > 4.2 {
                return match(
                    metricName: latest.name,
                    severity: .medium,
                    currentValue: latest.valueText,
                    suggestedAction: "建议 3 月复查甲状腺功能",
                    todoTitle: "复查甲状腺功能（TSH）",
                    checkupMonths: 3
                )
            }
        }

        if key.contains("血红蛋白") || key.contains("hb") {
            if latest.isAbnormal || latest.value < 115 {
                return match(
                    metricName: latest.name,
                    severity: .medium,
                    currentValue: latest.valueText,
                    suggestedAction: "建议血液科或补铁评估",
                    todoTitle: "血红蛋白偏低复查",
                    checkupMonths: 3
                )
            }
        }

        if key.contains("尿酸") {
            if latest.value > 420 {
                return match(
                    metricName: latest.name,
                    severity: .low,
                    currentValue: latest.valueText,
                    suggestedAction: "建议低嘌呤饮食，定期复查尿酸",
                    todoTitle: "复查尿酸",
                    checkupMonths: 6
                )
            }
        }

        if key.contains("alt") || key.contains("ast") || key.contains("转氨酶") {
            if latest.isAbnormal || isConsecutiveHigh(history, threshold: 40) {
                return match(
                    metricName: latest.name,
                    severity: .medium,
                    currentValue: latest.valueText,
                    suggestedAction: "建议 1–3 月复查肝功能",
                    todoTitle: "复查肝功能",
                    checkupMonths: 3
                )
            }
        }

        if key.contains("子宫肌瘤") {
            if historyTrend == .worsening {
                return match(
                    metricName: latest.name,
                    severity: .medium,
                    currentValue: latest.valueText,
                    suggestedAction: "建议妇科 B 超复查",
                    todoTitle: "妇科 B 超复查（子宫肌瘤）",
                    checkupMonths: 6
                )
            }
        }

        if key.contains("乳腺") && (latest.valueText.contains("4") || key.contains("bi-rads") && latest.value >= 4) {
            return match(
                metricName: latest.name,
                severity: .high,
                currentValue: latest.valueText,
                suggestedAction: "建议尽快乳腺专科就诊",
                todoTitle: "乳腺专科就诊",
                checkupMonths: 1
            )
        }

        if key.contains("骨密度") || key.contains("t值") || key.contains("t-值") {
            if latest.value <= -1.0 {
                return match(
                    metricName: latest.name,
                    severity: .low,
                    currentValue: latest.valueText,
                    suggestedAction: "建议补钙与负重运动，定期复查骨密度",
                    todoTitle: "复查骨密度",
                    checkupMonths: 12
                )
            }
        }

        return nil
    }

    /// 最新结果已正常则不再提醒；有多份报告时以最新一次为准
    private static func shouldSuppressRisk(latest: MetricSnapshot, history: [MetricSnapshot]) -> Bool {
        let sorted = history.sorted { $0.date < $1.date }
        if !latest.isAbnormal, sorted.count >= 2 {
            return true
        }
        return false
    }

    private static func adjustedSeverity(
        _ base: RiskSeverity,
        history: [MetricSnapshot],
        latest: MetricSnapshot
    ) -> RiskSeverity {
        guard history.count >= 2, trend(history) == .improving else { return base }
        switch base {
        case .high: return .medium
        case .medium: return .low
        case .low: return .low
        }
    }

    private static func adjustedAction(_ action: String, history: [MetricSnapshot]) -> String {
        guard history.count >= 2, trend(history) == .improving else { return action }
        return action + "（较上次有所改善，请遵医嘱随访）"
    }

    // MARK: - Helpers

    static func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
    }

    static func trend(_ history: [MetricSnapshot]) -> MetricTrend {
        guard history.count >= 2 else { return .unknown }
        let sorted = history.sorted { $0.date < $1.date }
        let delta = sorted.last!.value - sorted[sorted.count - 2].value
        if abs(delta) < 0.05 { return .stable }
        return delta > 0 ? .worsening : .improving
    }

    private static func isConsecutiveHigh(_ history: [MetricSnapshot], threshold: Double) -> Bool {
        let sorted = history.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return sorted.last.map { $0.value > threshold || $0.isAbnormal } ?? false }
        return sorted.suffix(2).allSatisfy { $0.value > threshold || $0.isAbnormal }
    }

    private static func severityRank(_ severity: RiskSeverity) -> Int {
        switch severity {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }
}
