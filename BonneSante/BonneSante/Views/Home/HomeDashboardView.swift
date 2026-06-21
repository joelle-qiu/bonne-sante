import SwiftUI
import SwiftData

/// 首页仪表盘（Bonne-Santé）
/// 信息层级：每日刷新数据（能量/营养）优先；复查待办置后。
/// @author jiali.qiu
struct HomeDashboardView: View {
    @Environment(\.healthContext) private var context

    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query private var goals: [UserGoal]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query private var cycleProfiles: [CycleProfile]
    @Query(sort: \Report.importDate, order: .reverse) private var reports: [Report]
    @Query(filter: #Predicate<RiskFlag> { !$0.isResolved }) private var riskFlags: [RiskFlag]
    @Query(sort: \TodoItem.dueDate) private var todos: [TodoItem]
    @Query private var checkupPlans: [CheckupPlan]

    @State private var showImport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let ctx = context {
                        phaseSection(ctx)
                        dailyEnergySection(ctx)
                        nutritionSection()
                        quickActions
                        cycleTipsSection(ctx)
                        foodListSection
                        checkupRemindersSection(ctx)
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
            .sheet(isPresented: $showImport) {
                ReportImportView()
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private func phaseSection(_ ctx: UnifiedHealthContext) -> some View {
        PhaseBar(
            label: ctx.cyclePhaseInfo.label,
            phase: ctx.cyclePhaseInfo.phase,
            daysUntilNextPeriod: ctx.cyclePhaseInfo.daysUntilNextPeriod,
            dataSourceLabel: ctx.cyclePhaseInfo.phase == .unknown ? nil : ctx.cyclePhaseInfo.dataSource.label
        )
    }

    @ViewBuilder
    private func dailyEnergySection(_ ctx: UnifiedHealthContext) -> some View {
        if let budget = ctx.dailyCalorieBudget, let remaining = ctx.remainingCalories {
            let resting = ctx.isUsingWatchData
                ? ctx.healthKitService.basalCaloriesBurned
                : (ctx.userGoal?.calculateBMR(currentWeight: ctx.currentWeight ?? 0) ?? 0)
            let active = ctx.isUsingWatchData
                ? ctx.healthKitService.activeCaloriesBurned
                : max(ctx.caloriesBurned - resting, 0)

            DailyEnergyBoard(
                remaining: remaining,
                budget: budget,
                consumed: ctx.caloriesConsumed,
                activeEnergy: active,
                basalEnergy: resting,
                totalBurned: ctx.caloriesBurned,
                isUsingWatchData: ctx.isUsingWatchData
            )
        } else {
            EmptyStateView(
                symbol: "target",
                title: "先设定减脂目标",
                message: "在「训练」页设置当前体重与目标体重后，这里会显示每日能量看板。",
                actionTitle: nil,
                action: nil
            )
            .frame(height: 200)
        }
    }

    private func nutritionSection() -> some View {
        let protein = todayEntries.reduce(0) { $0 + $1.protein }
        let carbs = todayEntries.reduce(0) { $0 + $1.carbohydrates }
        let fat = todayEntries.reduce(0) { $0 + $1.fat }
        let calories = todayEntries.reduce(0) { $0 + $1.calories }

        return NutritionMacroBars(
            protein: protein,
            carbs: carbs,
            fat: fat,
            calories: calories
        )
    }

    @ViewBuilder
    private func checkupRemindersSection(_ ctx: UnifiedHealthContext) -> some View {
        CompactCheckupReminders(plans: ctx.upcomingCheckupPlans)
    }

    @ViewBuilder
    private func cycleTipsSection(_ ctx: UnifiedHealthContext) -> some View {
        if ctx.cyclePhaseInfo.phase == .unknown {
            tipCard(ctx.cyclePhaseInfo.tip)
        } else {
            CycleTipsCard(phaseInfo: ctx.cyclePhaseInfo, compact: true)
        }
    }

    private func tipCard(_ tip: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Theme.adaptiveAccent(colorScheme))
            Text(tip)
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            NavigationLink {
                FoodInputView()
            } label: {
                Label("记录饮食", systemImage: "fork.knife")
            }
            .buttonStyle(MorandiQuickActionButtonStyle(variant: .primary))

            Button { showImport = true } label: {
                Label("导入报告", systemImage: "doc.text.viewfinder")
            }
            .buttonStyle(MorandiQuickActionButtonStyle(variant: .secondary))
        }
    }

    private var todayEntries: [FoodEntry] {
        let start = Calendar.current.startOfDay(for: Date())
        return allEntries.filter { $0.createdAt >= start }
    }

    private var foodListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日饮食")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                Spacer()
                if !todayEntries.isEmpty {
                    Text("\(todayEntries.count) 条")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }

            Group {
                if todayEntries.isEmpty {
                    Text("还没有记录，点击「记录饮食」开始。")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(todayEntries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                            FoodEntryRow(entry: entry)
                            if index < min(todayEntries.count, 3) - 1 {
                                Divider()
                            }
                        }
                        if todayEntries.count > 3 {
                            Text("还有 \(todayEntries.count - 3) 条记录")
                                .font(.caption2)
                                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                    }
                }
            }
            .morandiCard()
        }
    }

    private func refreshContext() async {
        await context?.refresh(
            foodEntries: allEntries,
            goals: goals,
            weightEntries: weightEntries,
            cycleProfiles: cycleProfiles,
            reports: reports,
            riskFlags: riskFlags,
            todos: todos,
            checkupPlans: checkupPlans
        )
    }
}

#Preview {
    HomeDashboardView()
        .modelContainer(for: [FoodEntry.self, UserGoal.self, WeightEntry.self, CycleProfile.self], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
