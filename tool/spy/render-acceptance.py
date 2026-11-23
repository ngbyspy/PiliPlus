"""Render a local acceptance-package page without registering a formal release."""

import argparse
import html
import json
from pathlib import Path
from urllib.parse import quote


def render(root, date, ios_source=None):
    root = Path(root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    assets = []
    cards = []
    for platform, description in [
        ("Windows", "完整解压后运行；沿用上游身份和原数据目录，可原地测试。"),
        ("Android", "独立安装的 Debug APK，与 SPY 正式版及上游版并存。"),
    ]:
        report = root / platform / f"build-{platform.lower()}.json"
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
                else:
                    asset["identity"] = data["windowsProfile"]
                assets.append(asset)
        button = (f'<a class="download" download href="{quote(asset["file"])}">下载测试包 · {asset["bytes"] / 1048576:.1f} MB</a>'
                  if asset else '<span class="pending">正在准备测试包</span>')
        identity = html.escape(asset.get("applicationId", "piliplus.exe") if asset else "")
        cards.append(f'<article><h2>{platform}</h2><p>{description}</p><code>{identity}</code>{button}</article>')
    workflow = "https://github.com/ngbyspy/PiliPlus/actions/workflows/spy-ipad.yml?query=branch%3Aspy%2Fdev"
    ios_status = "已提交云编译，等待用户报告结果" if ios_source else "待提交云编译"
    cards.append(f'<article><h2>iPad / iPhone</h2><p>可自签的测试 IPA，独立于正式版。</p><code>com.spy.piliPlus.dev</code><span class="pending">{ios_status}</span><a href="{workflow}">打开 GitHub 编译页面 ↗</a></article>')
    manifest = {"title": "第一批主题与分享测试包", "date": date,
                "features": ["S01", "S02", "T01", "T02", "T03", "T05"],
                "userAcceptance": "pending", "artifacts": assets,
                "ios": {"status": "awaiting_user_report" if ios_source else "not_submitted",
                        "sourceCommit": ios_source, "expectedBundleId": "com.spy.piliPlus.dev",
                        "workflow": workflow}}
    metadata = root / "_metadata"
    metadata.mkdir(exist_ok=True)
    (metadata / "acceptance-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checksums = "".join(f'{item["sha256"]}  {item["file"]}\n' for item in assets)
    (metadata / "SHA256SUMS.txt").write_text(checksums, encoding="utf-8")
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>第一批主题与分享测试包</title>
<style>*{box-sizing:border-box}body{margin:0;background:#f6f8fb;color:#17243b;font:16px/1.7 "Segoe UI","Microsoft YaHei",sans-serif}main{max-width:1080px;margin:auto;padding:36px 24px}a{color:#2058b8}h1{font-size:30px;margin:12px 0}h2{font-size:21px;margin:0 0 12px}.label{color:#556783}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin:28px 0}article{background:white;border:1px solid #dfe6ef;border-radius:16px;padding:24px;display:flex;flex-direction:column;gap:14px}article p{margin:0;flex:1}code{font-size:13px;overflow-wrap:anywhere}article a.download{display:block;text-align:center;padding:10px 12px;background:#2058b8;color:white;border-radius:8px;text-decoration:none}.pending{display:block;padding:10px;background:#edf1f6;border-radius:8px;color:#53627b}.guide{background:white;border:1px solid #dfe6ef;border-radius:16px;padding:24px}li{margin:8px 0}footer{margin-top:24px;font-size:14px;color:#53627b}@media(max-width:760px){.cards{grid-template-columns:1fr}main{padding:24px 16px}}</style>
<main><a href="../../index.html">← 正式版本目录</a><div class="label">本地验收包 · __DATE__</div><h1>第一批主题与分享测试包</h1><p>包含 S01、S02 分享文案，以及 T01 柔和配色、T02 高级材质、T03 连续圆角、T05 工具栏滚动渐变。功能仍待你逐项验收。</p><section class="cards">__CARDS__</section><section class="guide"><h2>如何比较效果</h2><p>打开「设置 → 外观设置 → 应用主题」。三个开关默认关闭，T03 圆角已固定应用。</p><ol><li>先固定同一种主题颜色与明暗模式，观察圆角。</li><li>打开「高级材质」，查看弹窗、菜单和导航栏。</li><li>保持高级材质开启，切换「工具栏随滚动渐变」，比较首页和搜索结果；也可试侧边栏及顶栏收起。</li><li>最后切换「柔和动态色」，比较颜色和文字可读性。</li></ol><p>S01、S02 随包回归，按约定免专项人工验收。请分别反馈每个平台各项功能的通过或问题。</p></section><footer><a href="_metadata/acceptance-manifest.json">构建与来源记录</a> · <a href="_metadata/SHA256SUMS.txt">SHA256 校验值</a></footer></main></html>'''
    (root / "index.html").write_text(page.replace("__DATE__", html.escape(date)).replace("__CARDS__", "".join(cards)), encoding="utf-8")
    (root.parent / "index.html").write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>PiliPlus 测试包</title><meta http-equiv="refresh" content="0;url=batch-1/index.html"><a href="batch-1/index.html">打开第一批测试包</a></html>', encoding="utf-8")
    print(root / "index.html")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--date", required=True)
    parser.add_argument("--ios-source")
    args = parser.parse_args()
    render(args.root, args.date, args.ios_source)
