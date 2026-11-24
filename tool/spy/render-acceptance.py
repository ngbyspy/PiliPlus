"""Render a local acceptance-package page without registering a formal release."""

import argparse
import html
import json
from pathlib import Path
from urllib.parse import quote


def render(root, date, ios_source=None, batch=1):
    root = Path(root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    metadata = root / "_metadata"
    metadata.mkdir(exist_ok=True)
    manifest_path = metadata / "acceptance-manifest.json"
    previous = json.loads(manifest_path.read_text(encoding="utf-8-sig")) if manifest_path.exists() else {}
    old_assets = {item["sha256"]: item for item in previous.get("artifacts", [])}
    title = {1: "第一批主题与分享测试包", 2: "第二批交互与状态修复测试包", 3: "第三批 iOS 液态玻璃验收"}[batch]
    features = (["S01", "S02", "T01", "T02", "T03", "T05"] if batch == 1 else
                ["N01", "N02", "N03", "P04", "P06", "P08", "L01", "L02", "L03", "L04", "L05", "L06", "L07", "I02"])
    if batch == 3:
        features = ["P05", "P07", "G01"]
    assets = []
    cards = []
    platforms = [] if batch == 3 else [
        ("Windows", "完整解压后运行；沿用上游身份和原数据目录，可原地测试。"),
        ("Android", "独立安装的 dev APK，默认以 Release 模式编译，与正式版并存。"),
    ]
    for platform, description in platforms:
        report = root / platform / f"build-{platform.lower()}.json"
        if platform == "Android" and (root / "Android-release" / "build-android.json").exists():
            report = root / "Android-release" / "build-android.json"
        asset = None
        if report.exists():
            data = json.loads(report.read_text(encoding="utf-8-sig"))
            if "artifact" in data and not data.get("failure"):
                file = Path(data["artifact"]["path"]).resolve()
                relative = file.relative_to(root).as_posix()
                asset = {"platform": platform, "file": relative,
                         "sourceCommit": data["sourceCommit"],
                         "sha256": data["artifact"]["sha256"],
                         "bytes": file.stat().st_size, "userAcceptance": "pending"}
                if platform == "Android":
                    asset["applicationId"] = data["androidVerification"]["applicationId"]
                    asset["debuggable"] = data["androidVerification"]["debuggable"]
                    asset["buildMode"] = data.get("packageProfile", {}).get("mode", "debug" if asset["debuggable"] else "release")
                    description = f'独立安装的 {asset["buildMode"].capitalize()} dev APK，与正式版及上游版并存。'
                else:
                    asset["identity"] = data["windowsProfile"]
                if asset["sha256"] in old_assets:
                    asset["userAcceptance"] = old_assets[asset["sha256"]].get("userAcceptance", "pending")
                assets.append(asset)
        button = (f'<a class="download" download href="{quote(asset["file"])}">下载测试包 · {asset["bytes"] / 1048576:.1f} MB</a>'
                  if asset else '<span class="pending">正在准备测试包</span>')
        identity = html.escape(asset.get("applicationId", "piliplus.exe") if asset else "")
        cards.append(f'<article><h2>{platform}</h2><p>{description}</p><code>{identity}</code>{button}</article>')
    workflow = "https://github.com/ngbyspy/PiliPlus/actions/workflows/spy-ipad.yml?query=branch%3Aspy%2Fdev"
    ios = {"status": "awaiting_user_report" if ios_source else "not_submitted",
           "sourceCommit": ios_source, "expectedBundleId": "com.spy.piliPlus.dev", "workflow": workflow}
    if previous.get("ios", {}).get("sourceCommit") == ios_source:
        ios.update(previous.get("ios", {}))
    ios_status = ("用户已报告验收通过" if ios["status"] == "user_accepted" else
                  "已提交云编译，等待用户报告结果" if ios_source else "待提交云编译")
    cards.append(f'<article><h2>iPad / iPhone</h2><p>可自签的测试 IPA，独立于正式版。</p><code>com.spy.piliPlus.dev</code><span class="pending">{ios_status}</span><a href="{workflow}">打开 GitHub 编译页面 ↗</a></article>')
    manifest = {"title": title, "date": date, "features": features,
                "userAcceptance": previous.get("userAcceptance", "pending"), "artifacts": assets, "ios": ios}
    if batch == 3:
        manifest.update({"manualAcceptanceFeatures": ["G01"],
                         "manualAcceptanceWaived": ["P05", "P07"],
                         "platformBuildScope": ["iOS"],
                         "windowsAndroidBuilds": "not_requested"})
    (metadata / "acceptance-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checksums = "".join(f'{item["sha256"]}  {item["file"]}\n' for item in assets)
    (metadata / "SHA256SUMS.txt").write_text(checksums, encoding="utf-8")
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>第一批主题与分享测试包</title>
<style>*{box-sizing:border-box}body{margin:0;background:#f6f8fb;color:#17243b;font:16px/1.7 "Segoe UI","Microsoft YaHei",sans-serif}main{max-width:1080px;margin:auto;padding:36px 24px}a{color:#2058b8}h1{font-size:30px;margin:12px 0}h2{font-size:21px;margin:0 0 12px}.label{color:#556783}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin:28px 0}article{background:white;border:1px solid #dfe6ef;border-radius:16px;padding:24px;display:flex;flex-direction:column;gap:14px}article p{margin:0;flex:1}code{font-size:13px;overflow-wrap:anywhere}article a.download{display:block;text-align:center;padding:10px 12px;background:#2058b8;color:white;border-radius:8px;text-decoration:none}.pending{display:block;padding:10px;background:#edf1f6;border-radius:8px;color:#53627b}.guide{background:white;border:1px solid #dfe6ef;border-radius:16px;padding:24px}li{margin:8px 0}footer{margin-top:24px;font-size:14px;color:#53627b}@media(max-width:760px){.cards{grid-template-columns:1fr}main{padding:24px 16px}}</style>
<main><a href="../../index.html">← 正式版本目录</a><div class="label">本地验收包 · __DATE__</div><h1>第一批主题与分享测试包</h1><p>包含 S01、S02 分享文案，以及 T01 柔和配色、T02 高级材质、T03 连续圆角、T05 工具栏滚动渐变。功能仍待你逐项验收。</p><section class="cards">__CARDS__</section><section class="guide"><h2>如何比较效果</h2><p>打开「设置 → 外观设置 → 应用主题」。三个开关默认关闭，T03 圆角已固定应用。</p><ol><li>先固定同一种主题颜色与明暗模式，观察圆角。</li><li>打开「高级材质」，查看弹窗、菜单和导航栏。</li><li>保持高级材质开启，切换「工具栏随滚动渐变」，比较首页和搜索结果；也可试侧边栏及顶栏收起。</li><li>最后切换「柔和动态色」，比较颜色和文字可读性。</li></ol><p>S01、S02 随包回归，按约定免专项人工验收。请分别反馈每个平台各项功能的通过或问题。</p></section><footer><a href="_metadata/acceptance-manifest.json">构建与来源记录</a> · <a href="_metadata/SHA256SUMS.txt">SHA256 校验值</a></footer></main></html>'''
    if batch == 3:
        page = page.replace("第一批主题与分享测试包", title)
        start = page.index('<h1>')
        end = page.index('<section class="cards">', start)
        page = page[:start] + f'<h1>{title}</h1><p>本批重点验收 iPhone / iPad 的液态玻璃底栏。P05 预缓冲随倍速更新、P07 延后补充画质请求经代码审查与模拟后纳入正式源码，免专项人工验收。本批不构建 Windows、Android。</p>' + page[end:]
        start = page.index('<section class="guide">')
        end = page.index('<footer>', start)
        page = page[:start] + '''<section class="guide"><h2>液态玻璃底栏验收步骤</h2><ol>
<li>安装本批测试 IPA，自签后仍使用 com.spy.piliPlus.dev。系统原生玻璃需要 iOS / iPadOS 26 或以上；旧系统会显示原底栏。</li>
<li>使用底栏布局，关闭「设置 → 外观设置 → 改用侧边栏」后按原设置要求重启；iPad 先用竖屏。横屏或开启侧边栏时，原有布局规则继续生效。</li>
<li>打开「设置 → 外观设置 → 液态玻璃底栏」。开关默认关闭、切换直接生效，不依赖「高级材质」或「悬浮底栏」开关。</li>
<li>先点选「首页、动态、我的」，再按住栏目横向滑动、松手；检查系统玻璃选中层是否跟手、最终栏目是否正确、文字是否清晰、角标及重复点击回顶/刷新是否正常。</li>
<li>观察明暗主题，打开弹窗后点其覆盖底栏的区域，检查是否误切栏目；如开启底栏随滚动收起，检查隐藏与唤出。iPad 再尝试旋转、分屏和窗口大小变化。</li>
<li>关闭「液态玻璃底栏」，应回到原底栏样式；再开启不应出现双底栏或选中状态不同步。</li>
</ol><p>P05/P07 随正常播放观察即可，无需为它们再安排专项验收。L04/L05 保留现状并停止改进，L07 已移除，会员购放弃，其余挂起。</p><p>反馈只需写：机型及系统版本、操作、实际效果。云编译结果由你报告，提交后不持续跟进。</p><p><a href="../batch-2/index.html">第二批历史包与记录</a> · <a href="../batch-1/index.html">第一批验收记录</a></p></section>''' + page[end:]
        page = page.replace('.cards{display:grid;grid-template-columns:repeat(3,1fr)', '.cards{display:grid;grid-template-columns:1fr;max-width:520px')
    elif batch == 2:
        page = page.replace("第一批主题与分享测试包", title)
        start = page.index('<h1>')
        end = page.index('<section class="cards">', start)
        page = page[:start] + f'<h1>{title}</h1><p>本批新增 14 项：底栏与浮动按钮修复、长按倍速恢复、画质缺档回退、时间字号、列表状态与请求隔离、搜索清空、返回位置和导入弹窗。保留第一批已验收功能。</p>' + page[end:]
        start = page.index('<section class="guide">')
        end = page.index('<footer>', start)
        page = page[:start] + '''<section class="guide"><h2>本批验收顺序</h2><ol>
<li>N01～N03：开启原有底栏随滚动隐藏设置。来回滚动、回到顶部、切换页面和切回前台，检查显隐是否稳定，隐藏按钮是否还会误触。</li>
<li>P04：先设定常用倍速，再反复长按、松手，检查是否恢复原速。P06：画质缺档时应回退到实际可用档位。P08：改变文字缩放，查看播放器时间文字是否同步更新。</li>
<li>L01～L06：查看推荐、历史、收藏和搜索的加载、空列表、失败及重试提示；切换账号和快速更换查询后不应混入旧结果。失败和乱序场景另有自动化测试。</li>
<li>L07：在视频详情滚动到简介或评论，从其他页面返回，检查位置是否保持。</li>
<li>I02：导入时连续点击确定只提交一次；取消弹窗再进入其他页面，原导入完成不应关闭新页面。</li>
</ol><p>请按平台反馈有问题的编号。Android dev 默认也使用 Release 编译，独立包名保证与正式版并存；历史 Debug 包仍按各自构建报告标注。</p><p><a href="acceptance-guide.html">逐项验收说明</a> · <a href="../batch-1/index.html">第一批验收记录</a></p></section>''' + page[end:]
    elif previous.get("userAcceptance", "pending") != "pending":
        page = page.replace("功能仍待你逐项验收。", "Windows、iOS 已验收通过；Android 功能认可，整体卡顿等待正式 Release 覆盖包复验。")
    (root / "index.html").write_text(page.replace("__DATE__", html.escape(date)).replace("__CARDS__", "".join(cards)), encoding="utf-8")
    destination = quote(root.name) + "/index.html"
    (root.parent / "index.html").write_text(f'<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>PiliPlus 测试包</title><meta http-equiv="refresh" content="0;url={destination}"><a href="{destination}">打开最新测试包</a></html>', encoding="utf-8")
    print(root / "index.html")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--date", required=True)
    parser.add_argument("--ios-source")
    parser.add_argument("--batch", type=int, choices=[1, 2, 3], default=1)
    args = parser.parse_args()
    render(args.root, args.date, args.ios_source, args.batch)
