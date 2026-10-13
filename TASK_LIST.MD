---

### 2. [TASK_LIST.MD]

```markdown
# Project Lumina - AI 開發微任務拆解清單

> **開發指引**：每個 Task 設計為 AI 可在 3-5 分鐘內完成並驗證的獨立單元。

## Phase 1: 基礎建設與權限 (Infrastructure & Setup)
- [x] **Task 1.1**: 初始化 Swift 6 SwiftUI 專案，建立 Clean Architecture 目錄結構 (App, Domain, Data, Presentation, Infrastructure)。
- [x] **Task 1.2**: 實作 `OSLog` 封裝，建立 `LoggerManager`，定義 Info, Debug, Error 三種日誌層級。
- [x] **Task 1.3**: 配置 App Sandbox，實作 `SecurityScopedBookmarkManager`，處理資料夾選取 (`NSOpenPanel`) 與權限持久化。

## Phase 2: 檔案系統與資料層 (Domain & Data)
- [x] **Task 2.1**: 定義 Domain 層的 `ImageItem` 與 `FolderNode` Entities。
- [x] **Task 2.2**: 實作 `FileSystemRepository`，使用 `FileManager` 讀取目錄內容與圖片檔案過濾。
- [x] **Task 2.3**: 整合 `FSEvents` (或 `DispatchSourceFileSystemObject`)，實作 `DirectoryMonitor`，當資料夾內容變更時發出通知。
- [x] **Task 2.4**: 引入 `GRDB` (SQLite)，建立快取資料庫 Schema，實作 `ExifCacheRepository`。

## Phase 3: 影像處理與效能 (Performance & Rendering)
- [x] **Task 3.1**: 實作 `ImageLoaderService`，封裝 `ImageIO` (CGImageSource) 進行極速縮圖生成。
- [x] **Task 3.2**: 實作基於 `Actor` 的記憶體快取 (Memory Cache) 機制，避免多執行緒讀寫衝突。

## Phase 4: UI 與互動層 (Presentation)
- [x] **Task 4.1**: 實作左側欄 `FolderTreeView` (SwiftUI List)，綁定 `DirectoryMonitor` 狀態。
- [x] **Task 4.2**: 實作主畫面 `ImageGridView` (LazyVGrid)，結合 `ImageLoaderService` 實現非同步載入縮圖。
- [x] **Task 4.3**: 實作全螢幕與鍵盤快捷鍵 (NSEvent / SwiftUI 焦點綁定)，支援方向鍵快速切換與 Space 鍵放大。
- [x] **Task 4.4**: 實作「我的最愛」資料夾功能，支援開啟資料夾後設定加入我的最愛，並在左側側邊欄快速點擊存取。

## Phase 5: 快速選片與檔案管理 (Advanced Culling & File Ops)
- [x] **Task 5.1**: 升級 SQLite DB Schema，新增 `rating` (0-5) 與 `is_tagged` (Bool) 欄位。
- [x] **Task 5.2**: 實作快速星級評等（按鍵 1-5）與標籤標記（按鍵 T），即時更新 SQLite 與畫面。
- [x] **Task 5.3**: 實作主畫面頂端「篩選工具列」，支援依星級或標籤快速過濾網格內容。
- [x] **Task 5.4**: 實作安全刪除機制（`Cmd + Delete`），調用 `NSWorkspace.shared.recycle` 將檔案移至垃圾桶，並發出檔案變更事件。
- [x] **Task 5.5**: 實作快速搬移（按鍵 M），支援設定挑選資料夾並一鍵將選取照片搬移過去。

## Phase 6: 專業影像 HUD 與效能增強 (Photo Analytics & Prefetch Engine)
- [x] **Task 6.1**: 實作即時亮度直方圖（Histogram），在詳細檢視中分析圖片並利用 SwiftUI 繪製直方圖曲線。
- [x] **Task 6.2**: 實作右側「詳細資訊欄（Details Sidebar）」，展示完整 EXIF 參數（如相機型號、快門、光圈、焦距、檔案大小、路徑等）。
- [x] **Task 6.3**: 實作相鄰圖片預載入引擎（Look-Ahead Prefetcher），在背景非同步快取當前照片前後各 2 張的大圖/縮圖，以實現零卡頓切換。