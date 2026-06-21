import Foundation

/// 跨报告指标趋势数据（按分类合并、相对指数可比）
/// @author jiali.qiu
enum HealthMetricTrendEngine {

    struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let valueText: String
        let isAbnormal: Bool
        var sizeMillimeters: Double?
        var severityRank: Int = 0
        var assessmentNote: String = ""
    }

    struct Series: Identifiable {
        let id: String
        let displayName: String
        let unit: String
        let points: [DataPoint]
    }

    struct NormalizedPoint: Identifiable {
        let id = UUID()
        let date: Date
        let index: Double
        let valueText: String
        let isAbnormal: Bool
    }

    struct TrendLine: Identifiable {
        let id: String
        let displayName: String
        let plainTitle: String
        let metricType: String
        let relatedTo: String
        let unit: String
        let points: [NormalizedPoint]
        let rawPoints: [DataPoint]
        let trend: MetricTrend
        let status: MetricTrendCatalog.HealthStatus
        let statusNote: String
        let latestValueText: String
        let firstValueText: String
        let severityRank: Int
        let assessmentNote: String

        var isNotable: Bool {
            if status == .stableGood { return false }
            if status == .singleRecord {
                if id == "imaging.lung_nodule" || id == "imaging.liver_lesion" {
                    return rawPoints.first?.isAbnormal == true
                }
                return severityRank >= 2 && (rawPoints.first?.isAbnormal == true)
            }
            return true
        }
    }

    struct TrendPanel: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let relatedSystems: [String]
        let lines: [TrendLine]

        var notableLines: [TrendLine] {
            lines.filter(\.isNotable).sorted { lhs, rhs in
                if lhs.severityRank != rhs.severityRank { return lhs.severityRank > rhs.severityRank }
                return lhs.status.sortPriority > rhs.status.sortPriority
            }
        }

        var singleRecordLines: [TrendLine] {
            lines.filter { $0.status == .singleRecord && !$0.isNotable }
                .sorted { lhs, rhs in
                    if lhs.severityRank != rhs.severityRank { return lhs.severityRank > rhs.severityRank }
                    let la = lhs.rawPoints.first?.isAbnormal == true
                    let ra = rhs.rawPoints.first?.isAbnormal == true
                    if la != ra { return la }
                    return lhs.plainTitle < rhs.plainTitle
                }
        }

        var stableLines: [TrendLine] {
            lines.filter { $0.status == .stableGood }
        }

        var hasComparableLines: Bool {
            !notableLines.isEmpty || !stableLines.isEmpty
        }
    }

    struct TrendOverview {
        let recovered: Int
        let newConcern: Int
        let ongoing: Int
        let improving: Int
        let stableGood: Int
        let singleRecord: Int
    }

    static func verifiedReportCount(from reports: [Report]) -> Int {
        reports.filter(\.isVerified).count
    }

    static func inferPanelId(forMetricName name: String) -> String? {
        MetricTrendCatalog.inferPanelId(forMetricName: name)
    }

    static func buildOverview(from reports: [Report]) -> TrendOverview {
        let lines = buildPanels(from: reports).flatMap(\.lines)
        return TrendOverview(
            recovered: lines.filter { $0.status == .recovered }.count,
            newConcern: lines.filter { $0.status == .newConcern }.count,
            ongoing: lines.filter { $0.status == .ongoing }.count,
            improving: lines.filter { $0.status == .improvingAbnormal }.count,
            stableGood: lines.filter { $0.status == .stableGood }.count,
            singleRecord: lines.filter { $0.status == .singleRecord }.count
        )
    }

    static func buildPanels(from reports: [Report]) -> [TrendPanel] {
        let verifiedCount = verifiedReportCount(from: reports)
        guard verifiedCount >= 2 else { return [] }

        let allSeries = buildSeries(from: reports, minimumPoints: 1)
        guard !allSeries.isEmpty else { return [] }

        return MetricTrendCatalog.panels.compactMap { meta in
            let matched = allSeries.filter { series in
                MetricTrendCatalog.inferPanelId(forMetricName: series.displayName) == meta.id
                    || MetricTrendCatalog.inferPanelId(forCanonicalKey: series.id) == meta.id
            }
            let lines = matched.compactMap { normalizeSeries($0, verifiedReportCount: verifiedCount) }
            guard !lines.isEmpty else { return nil }
            return TrendPanel(
                id: meta.id,
                title: meta.title,
                subtitle: meta.subtitle,
                relatedSystems: meta.relatedSystems,
                lines: lines
            )
        }
    }

    static func buildSeries(from reports: [Report], minimumPoints: Int = 2) -> [Series] {
        let verified = reports
            .filter(\.isVerified)
            .sorted {
                ReportDisplayFormatter.examDate(for: $0) < ReportDisplayFormatter.examDate(for: $1)
            }

        var buckets: [String: [(date: Date, metric: HealthMetric)]] = [:]
        var displayNames: [String: String] = [:]
        var units: [String: String] = [:]

        for report in verified {
            let date = ReportDisplayFormatter.examDate(for: report)
            for metric in report.metrics where metric.category == "检验" && hasComparableValue(metric) {
                let key = MetricNameCanonicalizer.canonicalKey(for: metric.name)
                buckets[key, default: []].append((date, metric))
                if displayNames[key] == nil || metric.name.count > (displayNames[key]?.count ?? 0) {
                    displayNames[key] = metric.name
                }
                if !metric.unit.isEmpty { units[key] = metric.unit }
            }
        }

        return buckets.compactMap { key, entries in
            var byDate: [Date: (date: Date, metric: HealthMetric)] = [:]
            for entry in entries { byDate[entry.date] = entry }
            let deduped = byDate.values.sorted { $0.date < $1.date }
            guard deduped.count >= minimumPoints else { return nil }

            let points = deduped.map {
                DataPoint(
                    date: $0.date,
                    value: $0.metric.value,
                    valueText: displayValueText($0.metric),
                    isAbnormal: $0.metric.isAbnormal,
                    severityRank: $0.metric.severityRank,
                    assessmentNote: $0.metric.assessmentNote
                )
            }
            return Series(
                id: key,
                displayName: displayNames[key] ?? key,
                unit: units[key] ?? "",
                points: points
            )
        }
    }

    private static func hasComparableValue(_ metric: HealthMetric) -> Bool {
        if metric.value != 0 { return true }
        let text = metric.valueText.lowercased()
        return text.contains("阳性") || text.contains("pos") || text.contains("neg")
            || text.contains("阴性") || text == "+" || text == "-"
    }

    private static func displayValueText(_ metric: HealthMetric) -> String {
        if !metric.valueText.isEmpty { return metric.valueText }
        if metric.unit.isEmpty { return String(metric.value) }
        return "\(metric.value) \(metric.unit)"
    }

    private static func normalizeSeries(_ series: Series, verifiedReportCount: Int) -> TrendLine? {
        let sortedRaw = series.points.sorted { $0.date < $1.date }
        if sortedRaw.count == 1 {
            guard verifiedReportCount >= 2 else { return nil }
            return singleRecordLine(series: series, point: sortedRaw[0])
        }
        guard sortedRaw.count >= 2 else { return nil }
        let baseline = sortedRaw.first?.value ?? 0
        let normalized: [NormalizedPoint]
        if baseline != 0 {
            normalized = sortedRaw.map { point in
                NormalizedPoint(
                    date: point.date,
                    index: (point.value / baseline) * 100,
                    valueText: point.valueText,
                    isAbnormal: point.isAbnormal
                )
            }
        } else {
            normalized = sortedRaw.map { point in
                NormalizedPoint(
                    date: point.date,
                    index: point.isAbnormal ? 115 : 100,
                    valueText: point.valueText,
                    isAbnormal: point.isAbnormal
                )
            }
        }
        let snapshots = sortedRaw.map {
            RiskAnalyzer.MetricSnapshot(
                name: series.displayName,
                value: $0.value,
                valueText: $0.valueText,
                unit: series.unit,
                date: $0.date,
                isAbnormal: $0.isAbnormal
            )
        }
        let metricTrend = RiskAnalyzer.trend(snapshots)
        let status = MetricTrendCatalog.classifyStatus(
            points: sortedRaw,
            canonicalKey: series.id,
            metricTrend: metricTrend
        )
        let info = MetricTrendCatalog.metricMeta(forCanonicalKey: series.id, fallbackName: series.displayName)
        let maxSeverity = sortedRaw.map(\.severityRank).max() ?? 0
        let latestNote = sortedRaw.last?.assessmentNote.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return TrendLine(
            id: series.id,
            displayName: series.displayName,
            plainTitle: info.plainTitle,
            metricType: info.metricType,
            relatedTo: info.relatedTo,
            unit: series.unit,
            points: normalized,
            rawPoints: sortedRaw,
            trend: metricTrend,
            status: status,
            statusNote: statusNote(for: status, points: sortedRaw, trend: metricTrend, canonicalKey: series.id),
            latestValueText: sortedRaw.last?.valueText ?? "",
            firstValueText: sortedRaw.first?.valueText ?? "",
            severityRank: maxSeverity,
            assessmentNote: latestNote
        )
    }

    private static func statusNote(
        for status: MetricTrendCatalog.HealthStatus,
        points: [DataPoint],
        trend: MetricTrend,
        canonicalKey: String
    ) -> String {
        guard points.count >= 2 else { return status.summaryHint }
        let first = points.first!
        let last = points.last!
        let firstTag = first.isAbnormal ? "异常" : "正常"
        let lastTag = last.isAbnormal ? "异常" : "正常"

        var parts: [String] = [status.summaryHint, "（\(firstTag) → \(lastTag)）"]

        if first.value != 0, last.value != 0 {
            let delta = last.value - first.value
            let pct = abs(delta / first.value) * 100
            if pct >= 2 {
                let dir = delta < 0 ? "下降" : "上升"
                parts.append("数值\(dir)约 \(String(format: "%.0f", pct))%")
            }
        }
        if trend != .unknown {
            parts.append(trend.rawValue)
        }
        return parts.joined(separator: " · ")
    }

    private static func singleRecordLine(series: Series, point: DataPoint) -> TrendLine {
        let info = MetricTrendCatalog.metricMeta(forCanonicalKey: series.id, fallbackName: series.displayName)
        let note = MetricTrendCatalog.singleRecordNote(
            date: point.date,
            valueText: point.valueText,
            isAbnormal: point.isAbnormal
        )
        let normalized = [
            NormalizedPoint(
                date: point.date,
                index: 100,
                valueText: point.valueText,
                isAbnormal: point.isAbnormal
            )
        ]
        return TrendLine(
            id: series.id,
            displayName: series.displayName,
            plainTitle: info.plainTitle,
            metricType: info.metricType,
            relatedTo: info.relatedTo,
            unit: series.unit,
            points: normalized,
            rawPoints: [point],
            trend: .unknown,
            status: .singleRecord,
            statusNote: note,
            latestValueText: point.valueText,
            firstValueText: point.valueText,
            severityRank: point.severityRank,
            assessmentNote: point.assessmentNote
        )
    }

    static func highlightMetrics(from report: Report) -> [HealthMetric] {
        report.metrics
            .filter { $0.category == "检验" && $0.isAbnormal && hasComparableValue($0) }
            .prefix(6)
            .map { $0 }
    }
}
