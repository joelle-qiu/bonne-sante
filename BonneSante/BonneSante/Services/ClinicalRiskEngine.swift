import Foundation

/// 与异常指标摘要对齐的临床风险分析（科室 + 序列 key + 影像趋势）
/// @author jiali.qiu
enum ClinicalRiskEngine {

    private static let departmentOrder = [
        "妇科", "泌尿科", "骨科康复", "胸外科", "肝胆外科", "内分泌科", "影像科", "心血管科", "口腔科"
    ]

    static func analyze(metrics: [HealthMetric]) -> [RiskAnalyzer.RuleMatch] {
        analyze(inputs: HealthProfileEngine.metricInputs(from: metrics))
    }

    static func analyze(snapshots: [RiskAnalyzer.MetricSnapshot]) -> [RiskAnalyzer.RuleMatch] {
        let inputs = snapshots.map {
            HealthProfileEngine.MetricInput(from: $0)
        }
        return analyze(inputs: inputs)
    }

    static func analyze(inputs: [HealthProfileEngine.MetricInput]) -> [RiskAnalyzer.RuleMatch] {
        let grouped = Dictionary(grouping: inputs) { HealthProfileEngine.riskSeriesKey(for: $0) }
        var matches: [RiskAnalyzer.RuleMatch] = []

        for (seriesKey, history) in grouped {
            let sorted = history.sorted { $0.date < $1.date }
            guard let latest = sorted.last else { continue }
            guard let match = matchSeries(
                seriesKey: seriesKey,
                latest: latest,
                history: sorted
            ) else { continue }
            matches.append(match)
        }

        return matches.sorted { lhs, rhs in
            let li = departmentOrder.firstIndex(of: lhs.department) ?? departmentOrder.count
            let ri = departmentOrder.firstIndex(of: rhs.department) ?? departmentOrder.count
            if li != ri { return li < ri }
            return severityRank(lhs.severity) > severityRank(rhs.severity)
        }
    }

    // MARK: - Series matching

    private static func matchSeries(
        seriesKey: String,
        latest: HealthProfileEngine.MetricInput,
        history: [HealthProfileEngine.MetricInput]
    ) -> RiskAnalyzer.RuleMatch? {
        let hasAbnormalHistory = history.contains { HealthProfileEngine.isEffectiveAbnormal($0) }
        if !HealthProfileEngine.isEffectiveAbnormal(latest), !hasAbnormalHistory {
            return nil
        }

        let displaySource = displayMetricForSeries(
            seriesKey: seriesKey,
            latest: latest,
            history: history
        )
        let display = HealthProfileEngine.abnormalDisplayItem(for: displaySource)
        let trend = seriesTrend(seriesKey: seriesKey, history: history)
        let blob = RiskAnalyzer.normalize(
            displaySource.name + displaySource.valueText + displaySource.assessmentNote + display.actionHint
        )

        if let findingMatch = matchFindingSeries(
            seriesKey: seriesKey,
            display: display,
            latest: displaySource,
            history: history,
            trend: trend,
            blob: blob
        ) {
            return findingMatch
        }

        return matchLabSeries(
            seriesKey: seriesKey,
            display: display,
            latest: displaySource,
            history: history,
            trend: trend,
            blob: blob
        )
    }

    /// 慢性病灶序列：展示用最近一条真实病灶记录，避免被后续「未见异常」超声覆盖
    private static func displayMetricForSeries(
        seriesKey: String,
        latest: HealthProfileEngine.MetricInput,
        history: [HealthProfileEngine.MetricInput]
    ) -> HealthProfileEngine.MetricInput {
        guard FindingNameCanonicalizer.isChronicLesionSeriesKey(seriesKey) else {
            if HealthProfileEngine.isEffectiveAbnormal(latest) { return latest }
            return history.last(where: { HealthProfileEngine.isEffectiveAbnormal($0) }) ?? latest
        }
        let sorted = history.sorted { $0.date < $1.date }
        let lesionPoints = sorted.filter { point in
            guard point.value > 0 else { return false }
            let primary = point.name + point.valueText + point.assessmentNote
            return FindingTrendCatalog.hasLesionEvidence(
                in: primary,
                sizeMillimeters: point.value,
                isAbnormal: point.isAbnormal
            )
        }
        if let lastLesion = lesionPoints.last { return lastLesion }
        if HealthProfileEngine.isEffectiveAbnormal(latest) { return latest }
        return history.last(where: { HealthProfileEngine.isEffectiveAbnormal($0) }) ?? latest
    }

    private static func matchFindingSeries(
        seriesKey: String,
        display: HealthProfileEngine.AbnormalDisplayItem,
        latest: HealthProfileEngine.MetricInput,
        history: [HealthProfileEngine.MetricInput],
        trend: MetricTrend,
        blob: String
    ) -> RiskAnalyzer.RuleMatch? {
        switch seriesKey {
        case "imaging.lung_nodule":
            return buildMatch(
                seriesKey: seriesKey,
                display: display,
                latest: latest,
                trend: trend,
                severity: .high,
                action: display.actionHint.isEmpty ? "建议年度胸部 CT 复查" : display.actionHint,
                todoTitle: "胸部 CT 复查（\(display.name)）",
                checkupMonths: 12
            )
        case "imaging.liver_lesion":
            return buildMatch(
                seriesKey: seriesKey,
                display: display,
                latest: latest,
                trend: trend,
                severity: .medium,
                action: display.actionHint.isEmpty ? "建议肝胆外科或影像科长期随访" : display.actionHint,
                todoTitle: "肝胆外科随访（肝血管瘤/FNH）",
                checkupMonths: 12
            )
        case "gyn.uterus_fibroid", "finding.uterus.fibroid":
            return buildMatch(
                seriesKey: seriesKey,
                display: display,
                latest: latest,
                trend: trend,
                severity: trend == .worsening ? .medium : .medium,
                action: display.actionHint.isEmpty ? "建议妇科 B 超复查" : display.actionHint,
                todoTitle: "妇科 B 超复查（子宫肌瘤）",
                checkupMonths: 6
            )
        case "imaging.breast_hyperplasia":
            return buildMatch(
                seriesKey: seriesKey,
                display: display,
                latest: latest,
                trend: trend,
                severity: .low,
                action: display.actionHint.isEmpty ? "建议定期自查，必要时乳腺外科随访" : display.actionHint,
                todoTitle: "乳腺随访（小叶增生）",
                checkupMonths: 12
            )
        case "gyn.cervix_erosion":
            return buildMatch(
                seriesKey: seriesKey,
                display: display,
                latest: latest,
                trend: trend,
                severity: .medium,
                action: display.actionHint.isEmpty ? "建议结合 TCT/HPV，宫颈专科随访" : display.actionHint,
                todoTitle: "宫颈专科随访",
                checkupMonths: 6
            )
        case "gyn.cervix_nabothian":
            return nil
        default:
            if latest.isClinicalFinding, display.priority == .recheckOrTreat {
                return buildMatch(
                    seriesKey: seriesKey,
                    display: display,
                    latest: latest,
                    trend: trend,
                    severity: display.severityRank >= 3 ? .medium : .low,
                    action: display.actionHint.isEmpty ? "建议按科室建议复查" : display.actionHint,
                    todoTitle: "\(display.department)复查（\(display.name)）",
                    checkupMonths: 6
                )
            }
            if latest.isClinicalFinding,
               display.priority == .routineFollowUp,
               FindingNameCanonicalizer.isChronicLesionSeriesKey(seriesKey) {
                return buildMatch(
                    seriesKey: seriesKey,
                    display: display,
                    latest: latest,
                    trend: trend,
                    severity: .medium,
                    action: display.actionHint.isEmpty ? "建议定期影像随访" : display.actionHint,
                    todoTitle: "\(display.department)随访（\(display.name)）",
                    checkupMonths: 12
                )
            }
            return nil
        }
    }

    private static func matchLabSeries(
        seriesKey: String,
        display: HealthProfileEngine.AbnormalDisplayItem,
        latest: HealthProfileEngine.MetricInput,
        history: [HealthProfileEngine.MetricInput],
        trend: MetricTrend,
        blob: String
    ) -> RiskAnalyzer.RuleMatch? {
        if shouldSuppressLabRisk(latest: latest, history: history) { return nil }

        switch seriesKey {
        case "lipid.ldl":
            guard latest.isAbnormal || latest.value > 3.4 else { return nil }
            return buildMatch(
                seriesKey: seriesKey,
                display: display,
                latest: latest,
                trend: trend,
                severity: .medium,
                action: display.actionHint.isEmpty ? "建议 3–6 月复查血脂，低脂饮食" : display.actionHint,
                todoTitle: "复查血脂（LDL）",
                checkupMonths: 6
            )
        case "lipid.total_cholesterol":
            guard latest.isAbnormal || latest.value > 5.2 else { return nil }
            return buildMatch(
                seriesKey: seriesKey,
                display: display,
                latest: latest,
                trend: trend,
                severity: .medium,
                action: display.actionHint.isEmpty ? "建议 3–6 月复查血脂" : display.actionHint,
                todoTitle: "复查血脂（总胆固醇）",
                checkupMonths: 6
            )
        default:
            break
        }

        let key = RiskAnalyzer.normalize(latest.name)
        if key.contains("脓细胞"), latest.isAbnormal || latest.value > 5 {
            return buildMatch(
                seriesKey: seriesKey,
                display: display,
                latest: latest,
                trend: trend,
                severity: .medium,
                action: display.actionHint.isEmpty ? "建议妇科门诊就诊" : display.actionHint,
                todoTitle: "妇科就诊（阴道分泌物）",
                checkupMonths: 1
            )
        }

        if key.contains("尿潜血") || key.contains("尿隐血"), latest.isAbnormal {
            return buildMatch(
                seriesKey: seriesKey,
                display: display,
                latest: latest,
                trend: trend,
                severity: .low,
                action: display.actionHint.isEmpty ? "建议复查尿常规" : display.actionHint,
                todoTitle: "复查尿常规（潜血）",
                checkupMonths: 3
            )
        }

        if latest.isAbnormal, display.priority == .recheckOrTreat {
            return buildMatch(
                seriesKey: seriesKey,
                display: display,
                latest: latest,
                trend: trend,
                severity: display.severityRank >= 3 ? .medium : .low,
                action: display.actionHint.isEmpty ? "建议按科室建议复查" : display.actionHint,
                todoTitle: "\(display.department)复查（\(display.name)）",
                checkupMonths: 3
            )
        }

        return nil
    }

    private static func buildMatch(
        seriesKey: String,
        display: HealthProfileEngine.AbnormalDisplayItem,
        latest: HealthProfileEngine.MetricInput,
        trend: MetricTrend,
        severity: RiskSeverity,
        action: String,
        todoTitle: String,
        checkupMonths: Int
    ) -> RiskAnalyzer.RuleMatch {
        let value = display.valueSummary.isEmpty
            ? HealthProfileEngine.compactRiskValue(for: latest)
            : display.valueSummary
        return RiskAnalyzer.RuleMatch(
            metricName: display.name,
            severity: severity,
            currentValue: value,
            trend: trend,
            suggestedAction: action,
            todoTitle: todoTitle,
            checkupMonths: checkupMonths,
            department: display.department,
            seriesKey: seriesKey
        )
    }

    // MARK: - Trend

    static func seriesTrend(
        seriesKey: String,
        history: [HealthProfileEngine.MetricInput]
    ) -> MetricTrend {
        let sorted = history.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return .unknown }

        if FindingNameCanonicalizer.isChronicLesionSeriesKey(seriesKey) {
            return chronicLesionTrend(seriesKey: seriesKey, history: sorted)
        }

        let snapshots = sorted.map { input in
            RiskAnalyzer.MetricSnapshot(
                name: input.name,
                value: input.value,
                valueText: input.valueText,
                unit: input.unit,
                date: input.date,
                isAbnormal: input.isAbnormal,
                severityRank: input.severityRank,
                assessmentNote: input.assessmentNote
            )
        }
        return RiskAnalyzer.trend(snapshots)
    }

    private static func chronicLesionTrend(
        seriesKey: String,
        history: [HealthProfileEngine.MetricInput]
    ) -> MetricTrend {
        let lesionPoints = history.filter { point in
            guard point.value > 0 else { return false }
            let primary = point.name + point.valueText + point.assessmentNote
            return FindingTrendCatalog.hasLesionEvidence(
                in: primary,
                sizeMillimeters: point.value > 0 ? point.value : nil,
                isAbnormal: point.isAbnormal
            )
        }
        let compared = lesionPoints.count >= 2 ? lesionPoints : history.filter { $0.value > 0 }
        guard compared.count >= 2 else { return .unknown }

        let first = compared.first!
        let last = compared.last!
        let blob = RiskAnalyzer.normalize(last.valueText + last.assessmentNote)
        if blob.contains("相仿") || blob.contains("稳定") || blob.contains("未见明显变化") {
            return .stable
        }

        if first.value > 0, last.value > 0 {
            let delta = last.value - first.value
            if abs(delta) < 0.5 { return .stable }
            return delta > 0 ? .worsening : .improving
        }
        return .unknown
    }

    private static func shouldSuppressLabRisk(
        latest: HealthProfileEngine.MetricInput,
        history: [HealthProfileEngine.MetricInput]
    ) -> Bool {
        let sorted = history.sorted { $0.date < $1.date }
        if !latest.isAbnormal, sorted.count >= 2 { return true }
        return false
    }

    private static func severityRank(_ severity: RiskSeverity) -> Int {
        switch severity {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }
}
