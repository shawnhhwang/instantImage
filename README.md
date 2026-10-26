# Project Lumina - Mac 原生極速影像瀏覽與快速選片器

Project Lumina 是一款專為 macOS 設計、以「檔案系統為核心 (File-System Driven)」的極速影像瀏覽與專業挑選（Culling）工具。其靈感源自經典的 ACDSee，旨在解決傳統相簿軟體強制「匯入」的緩慢等待，提供零延遲、高效能且安全的本地影像操作體驗。

## 🏗️ 系統架構 (Clean Architecture)
* **`App`**：應用程式生命週期管理、權限控制（Security-Scoped Bookmarks）。
* **`Domain`**：核心業務模型與介面定義（ImageItem, FolderNode）。
* **`Data`**：資料夾讀寫（FileSystemRepository）、EXIF 本地快取（GRDB SQLite）。
* **`Presentation`**：SwiftUI 原生極速網格、詳細資訊 HUD 與自訂視圖。
* **`Infrastructure`**：FSEvents 資料夾變更監聽、GPU 影像解碼（ImageIO & Metal）、系統級高靈敏度鍵盤攔截器。

---

## 🚀 雙架構硬體最佳化版本 (Dual-Architecture Native Optimization)

Project Lumina 深度針對 Mac 硬體架構進行差異化調校，提供兩種專用極速發行版本與一種通用版：

| 版本名稱 | 目標架構 | 專用硬體最佳化特點 |
| :--- | :--- | :--- |
| **`ProjectLumina-AppleSilicon.app`** | **Apple Silicon (arm64)**<br>(M1/M2/M3/M4 系列) | • 充份發揮 **統一記憶體架構 (UMA)** 超高頻寬（零複製紋理交換）<br>• 自動依效能核心擴展至 **6~16 路並行縮圖解碼**<br>• 高縱深 **Lookahead Prefetch (6 張)**，實現極速秒切<br>• 記憶體快取容量提升 1.5 倍 |
| **`ProjectLumina-Intel.app`** | **Intel Core / Xeon (x86_64)** | • 針對獨立顯卡 (AMD Radeon) 與內顯進行 PCIe 傳輸優化<br>• 導入**智慧多核心溫控管線**，避免長時間挑圖風扇狂轉與熱降頻<br>• 平衡式預載縱深 (3 張) 與防抖快取，兼顧順暢度與系統反應 |
| **`ProjectLumina-Universal.app`** | **Universal 2 (arm64 + x86_64)** | • 內建雙架構 Fat Binary，於任何 Mac 機型均可原生免 Rosetta 執行 |

### 🛠️ 編譯與打包指令
- **一鍵建置全部版本**：`./build_dual_versions.sh` 或 `./build_app.sh`
- **僅建置 Apple Silicon 版**：`./build_arm64.sh` 或 `./build_app.sh --arm64`
- **僅建置 Intel 版**：`./build_intel.sh` 或 `./build_app.sh --intel`

---

## ⌨️ 專業挑圖快捷鍵對照表 (ACDSee Culling Shortcuts)

為了實現無滑鼠的極速盲操選片，Project Lumina 整合了系統級的快速鍵處理。以下是支援的核心快捷鍵：

| 快捷鍵 | 對應功能 | 設計用途 |
| :--- | :--- | :--- |
| **`左 / 右方向鍵`** | 上一張 / 下一張 | 快速瀏覽相鄰影像 |
| **`上 / 下方向鍵`** | 2D 網格垂直換列移動 | 依目前欄數精準上下移動一列 |
| **`⇧ Shift + 方向鍵`** | 連續範圍連選 | 快速批次選取多張相片 |
| **`⌘ Cmd + 方向鍵`** | 直達首張 / 最後一張 | 快速跳轉至相簿開頭或結尾 |
| **`1` - `5` 鍵** | 設定星級評等 (1-5 星) | 將照片歸類星等（支援比對模式焦點格） |
| **`0` 鍵** | 清除星級評等 | 取消當前照片的星等 |
| **`T` 鍵** | 切換已標記 / 未標記 (Tag) | 快速勾選要保留的照片 |
| **`Cmd + Delete`** | 安全刪除照片（移至垃圾桶） | 挑片時快速汰換不良照片 |
| **`空白鍵 (Space)`** | 進入 / 退出高解析度詳細檢視 | 快速放大看清細節 |
| **`ESC 鍵`** | 退出詳細檢視 / 離開換臉確認 | 返回多圖網格畫面 |
| **`Z` 鍵 / 雙擊滑鼠** | 100% 像素對焦 / 換臉 2.2x 放大 | 局部細節對焦檢驗（換臉模式下同步放大雙圖） |
| **`S` 鍵** | 開啟 AI 換臉工作台 | 快速針對照片開啟 FaceFusion 換臉 |
| **`⌘R` 鍵** | 換臉比對 / 換臉批次確認 | 隨時切換至換臉前後驗證模式 |
| **`H` 鍵** | 快速轉存為 HEIC 格式 | 高壓縮比與極致畫質取代原檔 |
| **`E` 鍵** | 一鍵自動校光 (Auto Light) | 智慧動態範圍與亮暗部補償 |
| **`\` 鍵** | 前後對比分割簾 (Split Curtain) | 即時對比校正前後色彩與曝光差異 |
| **`F` 鍵** | 切換 macOS 原生全螢幕 | 沉浸式無干擾挑圖體驗 |

