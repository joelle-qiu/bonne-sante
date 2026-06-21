import Foundation

/// DeepSeek 报告整理指令（网页复制 + App 内 API 共用规则）
/// @author jiali.qiu
enum ReportDeepSeekPastePrompt {

    static let deepSeekChatURL = URL(string: "https://chat.deepseek.com")!

    // MARK: - 共用规则（App 内 OCR / 严重度 enrichment 同步引用）

    /// 严重度 0–5 简要分级（供 DeepSeek 标注 severityRank）
    static let severityRubric = """
【severityRank 分级 — 仅供 App 排序与随访提示，非诊断】
0 = 正常/阴性（未见明显异常）
1 = 轻微偏离（边缘升高、良性改变、无需紧急处理）
2 = 轻度异常（需 lifestyle 或常规复查，如轻度血脂异常）
3 = 需随访（稳定小结节、血管瘤、轻度超标，建议 3–12 月复查）
4 = 重点关注（新发结节/磨玻璃/占位、明显超标、尺寸增大趋势）
5 = 优先处理（危急值、高度可疑恶性描述、快速增大 — 建议尽快就医）
"""

    /// 化验指标规范化输出（DeepSeek 侧预拆分，减少 App 本地解析）
    static let metricFormatGuidance = """
【化验 metrics — 必须预拆为原子指标】
- 优先输出扁平原子行：每条含 name、value 或 valueText、unit、referenceRange、isAbnormal
- 同一检验组合（尿常规、血脂、血常规等）的子项分别输出；用 panel 标注组合名（如 panel=「尿常规」）
- 也可用嵌套格式：{"panel":"尿常规","section":"尿常规","items":[{子项1},{子项2}]}，items 内每条同样带 referenceRange
- referenceRange：报告原文逐字摘抄（如 "<3.4"、"0-5"、"neg"、"90-140"）；报告未写则留空，禁止用医学常识补
- isAbnormal：仅按原文 ↑↓、+/-、阳性/阴性、超标判断；禁止因组合整体异常就把所有子项标为异常
- 禁止把多个子项塞进一条的 detail 逗号串（旧格式仅作无法拆分时的兜底）
- section 取 基础数据/一般检查/血常规/尿常规/血液生化/…；既往史、身高体重血压归 section=「基础数据」
"""

    /// 跨次趋势对比字段要求
    static let trendFieldGuidance = """
【趋势对比字段 — 便于 App 跨日期对比】
- 每条 metric / finding 必须带 visitDate（yyyy-MM-dd），多次检查不可合并为一条
- 影像结论 detail 中尽量写出可量化信息：结节/占位/血管瘤的最大径（mm 或 cm，与原文一致）
- 化验 metrics 每条保留 value、unit、referenceRange、isAbnormal（见上文原子格式要求）
- 同一器官多次检查分别输出，title 保持稳定（如「肺部」「肝脏」），便于趋势归并
- assessmentNote：1 句中文，说明为何给出该 severityRank（如「5mm 磨玻璃结节，建议 3–6 月 CT 随访」）
- findings 可增 conclusion 字段：单独存放诊断结论（如「正常心电图」「未见明显异常」），detail 只放测量参数或影像描述
"""

    /// 影像 / 体格 / 主检结论 — 必须与 recommendations 对应
    static let imagingFindingsGuidance = """
【影像 / 体格 findings — 不得只写进 recommendations】
- recommendations 中每条异常结论，必须在 findings 中有独立条目（title 用器官或检查项名）
- 每条 finding 必须标注 morphology 与 organSite（封闭枚举，见下方 taxonomy），App 将据此自动归类，无需本地穷举术语
- morphologyTags 可选：附加形态（如纳氏囊肿可 morphology=cyst, morphologyTags=["cyst"]）
- 必填类型（报告提及则必须输出）：肝脏(含低回声/血管瘤)、甲状腺(回声欠均匀/结节)、乳腺(增生/结节)、子宫/附件(肌瘤/囊肿)、颈椎(生理曲度变直)、心电图(心律不齐)、宫颈(纳氏囊肿)、牙结石 等
- category：影像（肝/甲状腺/乳腺/颈椎/心肺）、妇科（宫颈囊肿/肌瘤/阴道）、心电图、外科/其他（牙结石）
- title 稳定简短：如「肝脏」「甲状腺」「乳腺」「颈椎」「子宫颈」；detail 放影像描述；conclusion 放「血管瘤可能」等诊断性短语
- isAbnormal：除明确「未见明显异常/正常」外均为 true；血管瘤/囊肿/增生/曲度变直/心律不齐/结石 等 severityRank≥2
- assessmentNote：摘抄该条对应的主检建议（随访/专科/复查），便于 App 摘要展示
- 禁止把肝血管瘤、颈椎问题、囊肿等仅写在 recommendations 而不写 findings
"""

    /// DeepSeek 必须为每条 finding 填写的形态 / 部位标签
    static let findingTaxonomyGuidance = """
【finding 形态 / 部位标签 — morphology + organSite（必填）】
morphology 主形态（单选，英文枚举）：
  cyst=囊肿/纳氏囊肿/腺囊肿 | nodule=结节/占位 | tumor=肿瘤/癌
  hemangioma=血管瘤/低回声区 | hyperplasia=增生 | fibroid=肌瘤
  stone=结石 | arrhythmia=心律不齐 | structural=曲度变直/退变等结构改变
  infection=感染/炎症/阳性 | erosion=糜烂样改变 | calcification=钙化
  echo_abnormal=回声欠均匀等非特异性回声异常 | lipid=血脂类 | normal=明确正常 | other=无法归类

organSite 部位（单选，英文枚举）：
  liver | thyroid | breast | uterus | cervix | ovary | spine | heart
  kidney | lung | gallbladder | pancreas | dental | bladder | prostate | eye | skin | blood | other

示例：
- 子宫颈腺囊肿（纳氏囊肿）→ morphology=cyst, organSite=cervix
- 肝低回声血管瘤可能 → morphology=hemangioma, organSite=liver
- 颈椎生理曲度变直 → morphology=structural, organSite=spine
- 双侧甲状腺回声欠均匀 → morphology=echo_abnormal, organSite=thyroid
- 窦性心律不齐 → morphology=arrhythmia, organSite=heart, category=心电图

【CT/MRI 长期随访 — 肺结节 / 肝血管瘤 专用】
- 每次 CT/MRI 单独一条 finding，visitDate 必填（多次检查不可合并）
- 跨次 MRI 汇总粘贴：在同一 JSON 的 findings 数组内按 visitDate 拆成多条「肝脏」，禁止把三次检查塞进一条 detail
- 肺磨玻璃结节：morphology=nodule, organSite=lung
- 肝血管瘤/FNH：morphology=hemangioma, organSite=liver；同一 visitDate 仍用一条 finding（血管瘤+FNH 同框），但尺寸须分开写

【病灶尺寸 — 必填结构化字段（App 趋势优先读取，比长 detail 更可靠）】
每条肺结节 / 肝血管瘤 finding 除 detail 外必须填写：
- primarySizeMm：趋势主径（数字，单位 mm）。肺结节写磨玻璃主结节长径；肝血管瘤写「较大灶」最大径（cm 须换算，如 6×3.9cm → 60）
- secondarySizeMm：次要灶最大径 mm（可选）。肝左内叶 FNH 如 1.7×1.3cm → 17；肺微小结节范围上限如 3-5mm → 5
- ctValueHu：肺结节 CT 值整数（可选，如 -648）。仅主结节填写

detail 书写规范（detail 仍保留完整影像描述，但第一行建议尺寸摘要）：
- 第一行格式：【尺寸】主病灶约XXmm（原文尺寸）；次要灶…；CT值-XXXHu。
- 肺：主结节长径 mm + CT Hu；微小结节写范围不混入主径
- 肝：较大灶写 cm 或 mm（如 6×3.9cm 或 14mm×25mm）；FNH 单独写 1.7×1.3cm；介入术后写「较前减小」于 conclusion/assessmentNote
- 禁止在 primarySizeMm 中填 FNH 尺寸；禁止把 14 和 25 只填较小值

示例（肝介入术后 2025-09-05）：
primarySizeMm=25, secondarySizeMm=17, detail 首行「【尺寸】血管瘤较大灶约25mm（14mm×25mm）；FNH约17mm（1.7×1.3cm）。」

示例（肺 CT 2026-06-04）：
primarySizeMm=5, secondarySizeMm=5, ctValueHu=-709, detail 首行「【尺寸】磨玻璃主结节约5mm；微小结节3-5mm；CT值-709Hu。」

- severityRank：磨玻璃结节 / 多发血管瘤 ≥3；稳定相仿仍 ≥3
- assessmentNote：写随访间隔（如 3–6 月 CT）及与前片对比（相仿/增大/减小）
"""

    /// 功能性检查（心电图等）与正常项结论提取
    static let clinicalFindingGuidance = """
【功能性检查 / 正常结论 — 必须拆分清晰】
- 心电图：category=「心电图」，title=「心电图」；detail 只放心率/PR/QRS/QT 等参数；conclusion 放「正常心电图」等诊断结论
- 若报告仅有参数+句号+结论，务必写入 conclusion，不要全部塞进 detail
- 正常影像/心肺/甲状腺等：conclusion 写「未见明显异常」类原文；assessmentNote 写 1 句随访提示
- isAbnormal 按报告原文判断；正常项 severityRank=0
"""

    /// 多 visit JSON 示例（单行合法 JSON，含 panel 原子指标与嵌套 items）
    static let jsonExampleOneLine = """
{"examDate":"2025-10-31","assessmentNote":"建议按主检建议分别随访","metrics":[{"name":"尿潜血","valueText":"+","unit":"","referenceRange":"neg","isAbnormal":true,"panel":"尿常规","section":"尿常规","visitDate":"2025-10-31","severityRank":1,"assessmentNote":"尿潜血阳性，建议复查"},{"name":"低密度脂蛋白","value":3.52,"valueText":"3.52","unit":"mmol/L","referenceRange":"<3.4","isAbnormal":true,"section":"血液生化","visitDate":"2025-10-31","severityRank":2,"assessmentNote":"超出参考上限，建议 3 月复查血脂"}],"findings":[{"category":"影像","title":"肝脏","detail":"肝内低回声区","conclusion":"血管瘤可能","morphology":"hemangioma","organSite":"liver","isAbnormal":true,"visitDate":"2025-10-31","severityRank":3,"assessmentNote":"建议进一步专科排查"},{"category":"影像","title":"甲状腺","detail":"双侧腺体回声欠均匀","conclusion":"","morphology":"echo_abnormal","organSite":"thyroid","isAbnormal":true,"visitDate":"2025-10-31","severityRank":2,"assessmentNote":"建议内分泌科随访并结合甲功"},{"category":"影像","title":"颈椎","detail":"生理曲度变直","conclusion":"","morphology":"structural","organSite":"spine","isAbnormal":true,"visitDate":"2025-10-31","severityRank":2,"assessmentNote":"无症状可观察，有头晕手麻请专科就诊"},{"category":"妇科","title":"子宫颈","detail":"腺囊肿","conclusion":"纳氏囊肿","morphology":"cyst","organSite":"cervix","morphologyTags":["cyst"],"isAbnormal":true,"visitDate":"2025-10-31","severityRank":1,"assessmentNote":"建议定期复查"},{"category":"心电图","title":"心电图","detail":"窦性心律不齐","conclusion":"","morphology":"arrhythmia","organSite":"heart","isAbnormal":true,"visitDate":"2025-10-31","severityRank":1,"assessmentNote":"无不适可暂不处理，必要时专科就诊"}],"recommendations":["肝低回声，血管瘤可能：建议进一步专科排查","双侧甲状腺腺体回声欠均匀：建议内分泌科随访","颈椎生理曲度变直：无症状可观察","子宫颈腺囊肿（纳氏囊肿）：建议定期复查"]}
"""

    /// DeepSeek 网页 chat.deepseek.com 使用的完整指令
    static let instructionText = """
你是医疗检验与影像报告数据提取助手。我将上传 PDF/截图，或粘贴多次门诊检查记录（含 ### 日期 的 Markdown 病程）。

【严格要求 — 必须遵守】
1. 仅提取上传/粘贴内容中明确出现的文字，禁止引用报告以外的医学知识或自行诊断
2. 禁止补充报告中未写明的病因、治疗方案；recommendations 只摘抄原文建议段落
3. 无法确定的字段留空或省略，禁止猜测（尤其 referenceRange 不得臆造）
4. 数值、单位、参考范围、↑↓ 标记须与原文一致
5. 输出严格 JSON，不要 markdown 代码块，不要 JSON 以外的说明
6. detail、recommendations、assessmentNote 中禁止英文双引号 "，改用「」
7. 输出前自检：必须是 JSON.parse 可解析的合法 JSON

\(severityRubric)

\(metricFormatGuidance)

\(trendFieldGuidance)

\(clinicalFindingGuidance)

\(imagingFindingsGuidance)

\(findingTaxonomyGuidance)

【输出格式 — 一个完整 JSON 对象】
\(jsonExampleOneLine)

【字段说明】
- examDate：最近一次检查日期 yyyy-MM-dd（可省略，以各条 visitDate 为准）
- assessmentNote：主检总评/随访建议摘要（可选，顶层一条）
- visitDate：每条 metric/finding 所属检查日期（多次 CT/MRI/化验必填，不可省略）
- metrics：检验数值（含身高体重血压）；优先扁平原子行；panel=组合名；或 panel+items[] 嵌套
- 每条 metric 字段：name、value/valueText、unit、referenceRange、isAbnormal、section、visitDate、severityRank、assessmentNote
- findings：影像/体格/妇科/心电图等；category 取 检验/影像/妇科/外科/心电图/其他；可选 conclusion 字段
- 每条 finding 必填 morphology、organSite（见 taxonomy）；可选 morphologyTags 数组
- 肺结节/肝血管瘤 finding 必填 primarySizeMm；可选 secondarySizeMm、ctValueHu（见 CT/MRI 随访指引）
- recommendations：主检建议原文逐条摘抄

【复制提示】
完成后请复制完整 JSON 粘贴到 App「DeepSeek 整理结果」输入框。

请开始提取。
"""

    /// App 内 OCR 结构化 system 提示（与网页指令对齐）
    static let ocrStructuredSystemPrompt = """
你是医疗检验报告结构化助手。用户已完成设备端 OCR，你将收到脱敏纯文本。
请提取全部检验指标、异常发现与主检建议，输出严格 JSON，不要 markdown 代码块。

示例：
\(jsonExampleOneLine)

规则：
- 每条 metric/finding 带 visitDate（yyyy-MM-dd）；能从文本推断检查日期时必须填写
- metrics 必须预拆为原子指标：每条 name + value/valueText + unit + referenceRange + isAbnormal
- 同一组合用 panel 标注，或输出 panel + items[] 嵌套；禁止多个子项塞进一条 detail
- referenceRange 仅摘抄报告原文，未写则留空
- findings：影像/体格/妇科定性结论；正常描述 isAbnormal=false
- recommendations：「建议」「异常检查结果」段落原文逐条摘抄
- 忽略表头、审核者行、医院宣传文字
- 单位：mmol/L、U/L、μmol/L、g/L、mmHg
- 填写 severityRank 与 assessmentNote（见分级规则）
- 肺结节/肝血管瘤须填 primarySizeMm；可选 secondarySizeMm、ctValueHu

\(metricFormatGuidance)

\(imagingFindingsGuidance)

\(findingTaxonomyGuidance)

\(clinicalFindingGuidance)
"""

    /// App 内严重度 enrichment system 提示
    static let rankingSystemPrompt = """
你是医疗数据整理助手。用户已完成 OCR/粘贴解析，请为每条指标或结论补全严重度、章节与简要判断依据。
输出严格 JSON（无 markdown）：
{"items":[{"index":0,"severityRank":4,"section":"影像检查","category":"影像","assessmentNote":"5mm 磨玻璃结节，建议 CT 随访对比"}]}

规则：
- severityRank：0 正常，1 轻微 … 5 需优先关注
- section：一般检查、血常规、血液生化、凝血功能、心脏标志物、感染标志物、甲状腺功能、影像检查、其他
- category（findings）：检验/影像/妇科/外科/其他
- assessmentNote：1 句中文，说明分级依据与随访关注点（非诊断）
- index 对应输入列表顺序，不要遗漏异常项

\(severityRubric)
"""
}
