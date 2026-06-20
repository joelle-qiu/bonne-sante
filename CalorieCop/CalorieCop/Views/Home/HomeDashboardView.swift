import SwiftUI
import SwiftData

/// 首页仪表盘（Bonne-Santé）
/// @author jiali.qiu
struct HomeDashboardView: View {
    @Environment(\.healthContext) private var context

    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query private var goals: [UserGoal]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query private var cycleProfiles: [CycleProfile]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let ctx = context {
                        phaseSection(ctx)
                        calorieRingSection(ctx)
                        tipCard(ctx.cyclePhaseInfo.tip)
                        quickActions
                        macroSection(ctx)
                        foodListSection
                    } else {
                        ProgressView("加载中…")
                    }
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.vertical, 16)
            }
            .background(Theme.pageBackground(colorScheme).ignoresSafeArea())
            .navigationTitle("仪表盘")
            .task { await refreshContext() }
            .refreshable { await refreshContext() }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private func phaseSection(_ ctx: UnifiedHealthContext) -> some View {
        PhaseBar(label: ctx.cyclePhaseInfo.label, phase: ctx.cyclePhaseInfo.phase)
    }

    @ViewBuilder
    private func calorieRingSection(_ ctx: UnifiedHealthContext) -> some View {
        if let budget = ctx.dailyCalorieBudget, let remaining = ctx.remainingCalories {
            VStack(spacing: 8) {
                CircularProgress(
                    remaining: remaining,
                    budget: budget,
                    consumed: ctx.caloriesConsumed
                )
                .frame(maxWidth: .infinity)

                Text(ctx.isUsingWatchData ? "消耗数据来自 Apple Watch" : "消耗数据基于身体估算")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .morandiCard()
        } else {
            EmptyStateView(
                symbol: "target",
                title: "先设定减脂目标",
                message: "在「减脂」页设置当前体重与目标体重后，这里会显示每日热量预算。",
                actionTitle: nil,
                action: nil
            )
            .frame(height: 220)
        }
    }

    private func tipCard(_ tip: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.accent)
            Text(tip)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
        .morandiCard()
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            NavigationLink {
                FoodInputView()
            } label: {
                Label("记录饮食", systemImage: "fork.knife")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.primary)
                    .foregroundStyle(Theme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
            }

            Button {} label: {
                Label("导入报告", systemImage: "doc.text.viewfinder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent.opacity(0.35))
                    .foregroundStyle(Theme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
            }
            .disabled(true)
            .opacity(0.6)
        }
    }

    @ViewBuilder
    private func macroSection(_ ctx: UnifiedHealthContext) -> some View {
        let protein = todayEntries.reduce(0) { $0 + $1.protein }
        let carbs = todayEntries.reduce(0) { $0 + $1.carbohydrates }
        let fat = todayEntries.reduce(0) { $0 + $1.fat }

        VStack(alignment: .leading, spacing: 12) {
            Text("今日营养")
                .font(.headline)
            HStack {
                macroItem("蛋白", value: protein, unit: "g", color: .blue)
                macroItem("碳水", value: carbs, unit: "g", color: .orange)
                macroItem("脂肪", value: fat, unit: "g", color: .purple)
            }
        }
        .morandiCard()
    }

    private func macroItem(_ title: String, value: Double, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            Text("\(Int(value))\(unit)")
                .font(.title3.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var todayEntries: [FoodEntry] {
        let start = Calendar.current.startOfDay(for: Date())
        return allEntries.filter { $0.createdAt >= start }
    }

    private var foodListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日饮食")
                .font(.headline)
            if todayEntries.isEmpty {
                Text("还没有记录，点击上方「记录饮食」开始。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                FoodListView()
            }
        }
        .morandiCard()
    }

    private func refreshContext() async {
        await context?.refresh(
            foodEntries: allEntries,
            goals: goals,
            weightEntries: weightEntries,
            cycleProfiles: cycleProfiles
        )
    }
}

#Preview {
    HomeDashboardView()
        .modelContainer(for: [FoodEntry.self, UserGoal.self, WeightEntry.self, CycleProfile.self], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
