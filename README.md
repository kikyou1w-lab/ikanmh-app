# 漫小肆 (ikanmh-app)

漫小肆漫画站的 iOS 原生阅读器（SwiftUI，无第三方依赖）。
数据只走自建 API `https://ikanmh-api.kikyou1w.workers.dev`，
不加载原站网页、不接任何广告 SDK，全程无广告。

功能：首页（最近更新 / 本月人气 / 完结优选）、书库（题材 / 地区 / 进度筛选 +
翻页）、排行（新书榜 / 总榜 / 月榜 / 完结榜 / 推荐）、搜索、漫画详情（章节列表）、
竖屏章节阅读（点按隐藏界面、上一话 / 目录 / 下一话）、本地收藏与阅读历史。

## 本地构建（需要 Mac + Xcode 16）

```bash
brew install xcodegen
xcodegen generate
open Ikanmh.xcodeproj
```

## CI 出未签名 .ipa

每次推到 `main`（或手动触发）都会在 GitHub Actions 里编译并上传
未签名 `.ipa`：Actions → Artifacts → `漫小肆-unsigned-ipa` 下载，
再用 ESign 等工具在手机上自己签名安装。不提交 App Store，不收费。
