import Foundation

/// 跨报告检查结论（findings）趋势
/// @author jiali.qiu
enum HealthFindingTrendEngine {

    struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let valueText: String
        let isAbnormal: Bool
        let sizeMillimeters: Double?
        let detailText: String
        var severityRank: Int = 0
        var assessmentNote: String = ""
    }

    struct Series: Identifiable {
        let id: String
        let displayName: String
        let points: [DataPoint]
    }

    static func buildOverview(from reports: [Report]) -> HealthMetricTrendEngine.TrendOverview {
        let lines = buildPanels(from: reports).flatMap(\.lines)
        return HealthMetricTrendEngine.TrendOverview(
            recovered: lines.filter { $0.status == .recovered }.count,
            newConcern: lines.filter { $0.status == .newConcern }.count,
            ongoing: lines.filter { $0.status == .ongoing }.count,
            improving: lines.filter { $0.status == .improvingAbnormal }.count,
            stableGood: lines.filter { $0.status == .stableGood }.count,
            singleRecord: lines.filter { $0.status == .singleRecord }.count
        )
    }

    static func buildPanels(from reports: [Report]) -> [HealthMetricTrendEngine.TrendPanel] {
        let verifiedCount = HealthMetricTrendEngine.verifiedReportCount(from: reports)
        guard verifiedCount >= 2 else { return [] }

        let allSeries = buildSeries(from: reports, minimumPoints: 1)
        guard !allSeries.isEmpty else { return [] }

        return FindingTrendCatalog.panels.compactMap { meta in
            let matched = allSeries.filter { series in
                FindingTrendCatalog.inferPanelId(forCanonicalKey: series.id) == meta.id
            }
            let lines = matched.compactMap { normalizeSeries($0, verifiedReportCount: verifiedCount) }
            guard !lines.isEmpty else { return nil }
            return HealthMetricTrendEngine.TrendPanel(
                id: "finding.\(meta.id)",
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

        var buckets: [String: [(date: Date, entry: FindingNameCanonicalizer.Entry, severityRank: Int, assessmentNote: String, storedSizeMM: Double)]] = [:]
        var displayNames: [String: String] = [:]

        for report in verified {
            let reportDate = ReportDisplayFormatter.examDate(for: report)
            for metric in report.metrics where isTrendEligibleFinding(metric) {
                for entry in FindingNameCanonicalizer.entries(from: metric) {
                    let seriesKey = FindingNameCanonicalizer.normalizedTrendKey(entry.canonicalKey, metric: metric)
                    guard FindingNameCanonicalizer.isLesionFollowUpDataPoint(
                        seriesKey: seriesKey,
                        entry: entry,
                        metric: metric
                    ) else { continue }
                    let pointDate = lesionPointDate(metric: metric, reportDate: reportDate)
                    let storedSize = metric.value > 0 ? metric.value : 0
                    buckets[seriesKey, default: []].append((pointDate, entry, metric.severityRank, metric.assessmentNote, storedSize))
                    if displayNames[seriesKey] == nil {
                        displayNames[seriesKey] = FindingNameCanonicalizer.plainTitle(
                            for: seriesKey,
                            fallback: entry.displayName
                        )
                    }
                }
            }
        }

        return buckets.compactMap { key, entries in
            var byDate: [Date: (date: Date, entry: FindingNameCanonicalizer.Entry, severityRank: Int, assessmentNote: String, storedSizeMM: Double)] = [:]
            for item in entries {
                if let existing = byDate[item.date] {
                    byDate[item.date] = preferredEntry(existing: existing, incoming: item)
                } else {
                    byDate[item.date] = item
                }
            }
            let deduped = byDate.values.sorted { $0.date < $1.date }
            guard deduped.count >= minimumPoints else { return nil }

            let points = deduped.map { item in
                let entry = item.entry
                let sizeMM = resolvedSizeMillimeters(
                    entry: entry,
                    storedSizeMM: item.storedSizeMM,
                    assessmentNote: item.assessmentNote
                )
                // 无尺寸时不使用占位数值 1，避免趋势页误显示「1.0 mm」
                let numeric = sizeMM ?? 0
                return DataPoint(
                    date: item.date,
                    value: numeric,
                    valueText: displayValueText(entry, sizeMillimeters: sizeMM, assessmentNote: item.assessmentNote),
                    isAbnormal: entry.isAbnormal,
                    sizeMillimeters: sizeMM,
                    detailText: entry.detailText,
                    severityRank: item.severityRank,
                    assessmentNote: item.assessmentNote
                )
            }
            return Series(
                id: key,
                displayName: displayNames[key] ?? key,
                points: points
            )
        }
    }

    static func inferPanelId(forFindingName name: String) -> String? {
        let stub = HealthMetric(
            name: name,
            value: 0,
            valueText: name,
            unit: "",
            category: "异常发现",
            reportSection: "影像检查"
        )
        guard let key = FindingNameCanonicalizer.canonicalKey(for: stub) else { return nil }
        return FindingTrendCatalog.inferPanelId(forCanonicalKey: key).map { "finding.\($0)" }
    }

    static func hasTrendData(from reports: [Report]) -> Bool {
        HealthMetricTrendEngine.verifiedReportCount(from: reports) >= 2
            && (!buildPanels(from: reports).isEmpty
                || !buildSeries(from: reports, minimumPoints: 1).isEmpty)
    }

    /// 可纳入结论趋势的 metric（异常发现 + 影像章节 + AI 标签）
    private static func isTrendEligibleFinding(_ metric: HealthMetric) -> Bool {
        FindingNameCanonicalizer.isTrendFindingMetric(metric)
    }

    // MARK: - Private

    private static func preferredEntry(
        existing: (date: Date, entry: FindingNameCanonicalizer.Entry, severityRank: Int, assessmentNote: String, storedSizeMM: Double),
        incoming: (date: Date, entry: FindingNameCanonicalizer.Entry, severityRank: Int, assessmentNote: String, storedSizeMM: Double)
    ) -> (date: Date, entry: FindingNameCanonicalizer.Entry, severityRank: Int, assessmentNote: String, storedSizeMM: Double) {
        let old = existing.entry
        let new = incoming.entry
        if old.isAbnormal != new.isAbnormal { return new.isAbnormal ? incoming : existing }
        let oldSize = old.sizeMillimeters ?? (existing.storedSizeMM > 0 ? existing.storedSizeMM : nil)
        let newSize = new.sizeMillimeters ?? (incoming.storedSizeMM > 0 ? incoming.storedSizeMM : nil)
        if let oldSize, let newSize {
            return newSize >= oldSize ? incoming : existing
        }
        if newSize != nil { return incoming }
        if new.detailText.count > old.detailText.count { return incoming }
        return existing
    }

    /// 优先解析文本尺寸，其次用入库时写入的 metric.value（趋势锚点）
    private static func resolvedSizeMillimeters(
        entry: FindingNameCanonicalizer.Entry,
        storedSizeMM: Double,
        assessmentNote: String
    ) -> Double? {
        if let parsed = entry.sizeMillimeters, parsed > 0 { return parsed }
        if storedSizeMM > 0 { return storedSizeMM }
        if let fromNote = FindingSizeParser.maxMillimeters(in: assessmentNote), fromNote > 0 {
            return fromNote
        }
        return nil
    }

    private static let bareOrganLabels: Set<String> = ["肝脏", "肺部", "肺", "肝", "双乳", "子宫", "宫颈", "甲状腺"]

    private static func displayValueText(
        _ entry: FindingNameCanonicalizer.Entry,
        sizeMillimeters: Double?,
        assessmentNote: String
    ) -> String {
        if let size = sizeMillimeters, size > 0 {
            return String(format: "%.1f mm", size)
        }
        if let fromNote = FindingSizeParser.maxMillimeters(in: assessmentNote), fromNote > 0 {
            return String(format: "%.1f mm", fromNote)
        }
        if entry.isAbnormal {
            let detail = entry.detailText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty, !bareOrganLabels.contains(detail), detail.count >= 6 {
                return String(detail.prefix(32))
            }
            return "异常（尺寸未标注）"
        }
        return "未见明显异常"
    }

    private static func normalizeSeries(_ series: Series, verifiedReportCount: Int) -> HealthMetricTrendEngine.TrendLine? {
        var lesionFiltered = FindingTrendCatalog.lesionTrendPoints(
            from: series.points,
            canonicalKey: series.id
        )
        // 慢性病灶：只对比有明确 mm 的记录，避免「44mm → 占位 1mm」误判 98% 缩小
        if FindingNameCanonicalizer.isChronicLesionSeriesKey(series.id) {
            let sized = series.points
                .filter { ($0.sizeMillimeters ?? 0) > 0 || $0.value > 0 }
                .sorted { $0.date < $1.date }
            if !sized.isEmpty {
                lesionFiltered = sized
            }
        }
        let sortedRaw = lesionFiltered.sorted { $0.date < $1.date }
        guard !sortedRaw.isEmpty else { return nil }
        if sortedRaw.count == 1 {
            guard verifiedReportCount >= 2 else { return nil }
            return singleRecordLine(series: series, point: sortedRaw[0])
        }
        guard sortedRaw.count >= 2 else { return nil }
        let baseline = sortedRaw.first?.value ?? 0
        let normalized: [HealthMetricTrendEngine.NormalizedPoint]
        if baseline != 0 {
            normalized = sortedRaw.map { point in
                HealthMetricTrendEngine.NormalizedPoint(
                    date: point.date,
                    index: (point.value / baseline) * 100,
                    valueText: point.valueText,
                    isAbnormal: point.isAbnormal
                )
            }
        } else {
            normalized = sortedRaw.map { point in
                HealthMetricTrendEngine.NormalizedPoint(
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
                unit: "mm",
                date: $0.date,
                isAbnormal: $0.isAbnormal
            )
        }
        let metricTrend = RiskAnalyzer.trend(snapshots)
        let status = FindingTrendCatalog.classifyStatus(
            points: sortedRaw,
            canonicalKey: series.id,
            metricTrend: metricTrend
        )
        let info = FindingTrendCatalog.findingMeta(forCanonicalKey: series.id, fallbackName: series.displayName)
        let maxSeverity = sortedRaw.map(\.severityRank).max() ?? 0
        let latestNote = sortedRaw.last?.assessmentNote.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = FindingNameCanonicalizer.plainTitle(for: series.id, fallback: info.plainTitle)

        return HealthMetricTrendEngine.TrendLine(
            id: series.id,
            displayName: title,
            plainTitle: title,
            metricType: info.findingType,
            relatedTo: info.relatedTo,
            unit: sortedRaw.contains(where: { $0.sizeMillimeters != nil }) ? "mm" : "",
            points: normalized,
            rawPoints: sortedRaw.map {
                HealthMetricTrendEngine.DataPoint(
                    date: $0.date,
                    value: $0.value,
                    valueText: $0.valueText,
                    isAbnormal: $0.isAbnormal,
                    sizeMillimeters: $0.sizeMillimeters,
                    severityRank: $0.severityRank,
                    assessmentNote: $0.assessmentNote
                )
            },
            trend: metricTrend,
            status: status,
            statusNote: statusNote(for: status, points: sortedRaw, trend: metricTrend, canonicalKey: series.id),
            latestValueText: sortedRaw.last.map { formatPointSizeLabel($0) } ?? "",
            firstValueText: sortedRaw.first.map { formatPointSizeLabel($0) } ?? "",
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
        let compared = FindingTrendCatalog.lesionTrendPoints(from: points, canonicalKey: canonicalKey)
        guard compared.count >= 2 else { return status.summaryHint }
        let first = compared.first!
        let last = compared.last!
        let firstTag = first.isAbnormal ? "异常" : "正常"
        let lastTag = last.isAbnormal ? "异常" : "正常"

        if FindingNameCanonicalizer.isChronicLesionSeriesKey(canonicalKey),
           first.isAbnormal && !last.isAbnormal {
            return "专项影像仍有记录；末次常规超声阴性不等同于病灶消失（仅供参考，请遵医嘱）"
        }

        var parts: [String] = [status.summaryHint, "（\(firstTag) → \(lastTag)）"]

        if FindingNameCanonicalizer.isChronicLesionSeriesKey(canonicalKey),
           let firstSize = first.sizeMillimeters, let lastSize = last.sizeMillimeters, firstSize > 0 {
            let delta = lastSize - firstSize
            if abs(delta) < 0.5 {
                let blob = RiskAnalyzer.normalize(last.detailText + last.valueText + last.assessmentNote)
                if blob.contains("相仿") || blob.contains("稳定") {
                    parts = ["病灶大小相近，建议继续按医嘱随访", "（\(firstTag) → \(lastTag)）"]
                } else {
                    parts.append("尺寸 \(String(format: "%.0f", firstSize))→\(String(format: "%.0f", lastSize)) mm")
                }
            } else {
                let dir = delta < 0 ? "缩小" : "增大"
                parts.append("尺寸\(dir) \(String(format: "%.0f", firstSize))→\(String(format: "%.0f", lastSize)) mm")
            }
        } else if let firstSize = first.sizeMillimeters, let lastSize = last.sizeMillimeters, firstSize > 0 {
            let delta = lastSize - firstSize
            if abs(delta) >= 0.5 {
                let dir = delta < 0 ? "缩小" : "增大"
                parts.append("尺寸\(dir) \(String(format: "%.0f", firstSize))→\(String(format: "%.0f", lastSize)) mm")
            }
        } else if !FindingNameCanonicalizer.isChronicLesionSeriesKey(canonicalKey),
                  first.value != 0, last.value != 0, first.sizeMillimeters != nil {
            let pct = abs((last.value - first.value) / first.value) * 100
            if pct >= 5 {
                let dir = last.value < first.value ? "缩小" : "增大"
                parts.append("约 \(String(format: "%.0f", pct))% \(dir)")
            }
        }

        if trend != .unknown {
            let trendLabel = chronicLesionTrendLabel(
                canonicalKey: canonicalKey,
                first: first,
                last: last,
                metricTrend: trend
            )
            parts.append(trendLabel)
        }
        return parts.joined(separator: " · ")
    }

    /// 慢性病灶：尺寸变化 <0.5 mm 视为持平，避免 5.3→5.0 误显示「↓ 改善」
    private static func chronicLesionTrendLabel(
        canonicalKey: String,
        first: DataPoint,
        last: DataPoint,
        metricTrend: MetricTrend
    ) -> String {
        guard FindingNameCanonicalizer.isChronicLesionSeriesKey(canonicalKey),
              let firstSize = first.sizeMillimeters,
              let lastSize = last.sizeMillimeters,
              firstSize > 0 else {
            return metricTrend.rawValue
        }
        if abs(lastSize - firstSize) < 0.5 {
            return MetricTrend.stable.rawValue
        }
        return metricTrend.rawValue
    }

    private static func singleRecordLine(series: Series, point: DataPoint) -> HealthMetricTrendEngine.TrendLine {
        let info = FindingTrendCatalog.findingMeta(forCanonicalKey: series.id, fallbackName: series.displayName)
        let title = FindingNameCanonicalizer.plainTitle(for: series.id, fallback: info.plainTitle)
        let note = MetricTrendCatalog.singleRecordNote(
            date: point.date,
            valueText: point.valueText,
            isAbnormal: point.isAbnormal
        )
        let normalized = [
            HealthMetricTrendEngine.NormalizedPoint(
                date: point.date,
                index: 100,
                valueText: point.valueText,
                isAbnormal: point.isAbnormal
            )
        ]
        return HealthMetricTrendEngine.TrendLine(
            id: series.id,
            displayName: title,
            plainTitle: title,
            metricType: info.findingType,
            relatedTo: info.relatedTo,
            unit: point.sizeMillimeters != nil ? "mm" : "",
            points: normalized,
            rawPoints: [
                HealthMetricTrendEngine.DataPoint(
                    date: point.date,
                    value: point.value,
                    valueText: point.valueText,
                    isAbnormal: point.isAbnormal,
                    sizeMillimeters: point.sizeMillimeters,
                    severityRank: point.severityRank,
                    assessmentNote: point.assessmentNote
                )
            ],
            trend: .unknown,
            status: .singleRecord,
            statusNote: note,
            latestValueText: formatPointSizeLabel(point),
            firstValueText: formatPointSizeLabel(point),
            severityRank: point.severityRank,
            assessmentNote: point.assessmentNote
        )
    }

    /// 慢性病灶优先用 metric.date（visitDate 入库值），避免 report.examDate 偏差
    private static func lesionPointDate(metric: HealthMetric, reportDate: Date) -> Date {
        let metricDay = Calendar.current.startOfDay(for: metric.date)
        let reportDay = Calendar.current.startOfDay(for: reportDate)
        if metricDay.timeIntervalSince1970 > 0, metricDay != reportDay {
            return metricDay
        }
        return reportDay
    }

    private static func formatPointSizeLabel(_ point: DataPoint) -> String {
        if let mm = point.sizeMillimeters, mm > 0 {
            return String(format: "%.1f mm", mm)
        }
        // value 仅存 mm 尺寸（≥2 避免与旧占位 1 混淆）；无尺寸时展示文案而非假 mm
        if point.value >= 2 {
            return String(format: "%.1f mm", point.value)
        }
        let trimmed = point.valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || bareOrganLabels.contains(trimmed) {
            return "尺寸未标注"
        }
        return trimmed
    }
}
