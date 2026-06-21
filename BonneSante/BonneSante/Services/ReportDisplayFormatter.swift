import Foundation

/// 报告列表 / 详情展示文案（以体检日期为主，弱化导入来源文件名）
/// @author jiali.qiu
enum ReportDisplayFormatter {

    private static let genericFileNames: Set<String> = [
        "DeepSeek 整理结果",
        "体检截图.jpg",
        "体检报告"
    ]

    static func examDate(for report: Report) -> Date {
        report.examDate ?? report.importDate
    }

    /// 时间线主标题，如「2025年10月31日」
    static func timelineTitle(for report: Report) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: examDate(for: report))
    }

    /// 详情页导航标题
    static func detailTitle(for report: Report) -> String {
        timelineTitle(for: report)
    }

    /// 左侧日期块：日
    static func dayComponent(for report: Report) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "d"
        return formatter.string(from: examDate(for: report))
    }

    /// 左侧日期块：月
    static func monthComponent(for report: Report) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter.string(from: examDate(for: report))
    }

    /// 左侧日期块：年
    static func yearComponent(for report: Report) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: examDate(for: report))
    }

    /// 副标题：指标与异常统计
    static func timelineSubtitle(for report: Report) -> String {
        let total = report.metrics.count
        let abnormal = report.metrics.filter(\.isAbnormal).count
        if abnormal > 0 {
            return "\(total) 项指标 · \(abnormal) 项异常"
        }
        return "\(total) 项指标"
    }

    /// 仅在文件名有实际含义时展示（PDF 原名等）
    static func sourceCaption(for report: Report) -> String? {
        let name = report.fileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !genericFileNames.contains(name) else { return nil }
        return name
    }

    /// 入库时优先使用体检日期命名
    static func preferredFileName(examDate: Date?, original: String) -> String {
        if let examDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return "\(formatter.string(from: examDate)) 体检报告"
        }
        if genericFileNames.contains(original) { return "体检报告" }
        return original
    }

    /// 短日期标签（趋势单次记录用）
    static func examDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    /// 按年份分组（时间线 Section 用）
    static func groupedByYear(_ reports: [Report]) -> [(year: String, reports: [Report])] {
        let sorted = reports.sorted {
            examDate(for: $0) > examDate(for: $1)
        }
        var groups: [(year: String, reports: [Report])] = []
        for report in sorted {
            let year = yearComponent(for: report) + "年"
            if groups.last?.year == year {
                groups[groups.count - 1].reports.append(report)
            } else {
                groups.append((year, [report]))
            }
        }
        return groups
    }
}
