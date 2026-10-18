# FaceFusion API Client

這個 Python 專案可以讀取本地端設定，將來源人臉（Source）與多張目標影像（Target）照片轉成 Base64 格式，依序拋給遠端 FaceFusion API 進行換臉，並將回傳的結果下載、轉換為 **100% 品質的 HEIC** 格式，最後以該檔案的 **Hash 值** 作為檔名儲存至指定資料夾。

本專案支援**動態參數輸入**與**批次按順序處理**。

---

## 🛠️ 環境準備

使用此工具前，請確保您已安裝 Python 3 並且安裝了必要的依賴套件。

```bash
pip install -r requirements.txt
```

---

## ⚙️ 配置文件說明 (`appsettings.json`)

[appsettings.json](file:///Users/shawnwang/Documents/agy/facefusion/appsettings.json) 讓您無須修改 Python 程式碼，即可靈活對接各種 FaceFusion API 或第三方 API。

| 參數名 | 類型 | 預設值 | 說明 |
| :--- | :--- | :--- | :--- |
| `api_url` | String | `http://127.0.0.1:7860/api/predict` | 遠端 FaceFusion / Gradio / API 伺服器網址 |
| `api_method` | String | `POST` | HTTP 請求方法 (`POST` 或 `GET`) |
| `api_headers` | Object | `{"Content-Type": "application/json"}` | 自訂 HTTP Headers (如 Bearer Token、Content-Type) |
| `payload_format` | Object | (看下方說明) | API 所需的 JSON 格式範本，支援自動代入 Base64 變數 |
| `response_type` | String | `json` | 遠端 API 回傳類型：`json` (回傳 base64 字串) 或 `binary` (直接回傳檔案二進位流) |
| `response_key` | String | `result` | 當 `response_type` 為 `json` 時，代表儲存 Base64 資料的 JSON Key (支援多層結構例如 `data.0` 或 `result.image`) |
| `source_image_path` | String | `source.jpg` | 預設的來源人臉相片路徑（可用 CLI 參數動態覆蓋） |
| `target_image_path` | String / Array | `target.jpg` | 預設的目標相片路徑，可設定為單一檔案、路徑陣列、資料夾路徑或 Glob 匹配字串（可用 CLI 參數動態覆蓋） |
| `output_dir` | String | `output` | 本地端儲存成果的資料夾路徑 |
| `hash_algorithm` | String | `sha256` | 成果檔案命名的雜湊演算法 (`sha256`, `md5`, `sha1`) |
| `include_base64_header` | Boolean | `false` | Base64 是否包含圖片格式前綴 (如 `data:image/jpeg;base64,...`) |
| `quality` | Integer | `100` | HEIC 儲存品質 (最大為 100 代表無損壓縮) |
| `hash_by_inputs` | Boolean | `true` | 是否藉由輸入的來源人臉、目標影像與配置設定計算檔名雜湊，以確保輸入一致時產出檔名/雜湊也一致（若為 `false` 則依據產出圖的檔案內容計算雜湊） |

---

## 🚀 執行程式

您可以使用預設的設定檔執行，也可以在命令列動態指定不同的來源人臉與目標照片。

### 1. 使用預設 `appsettings.json` 執行
```bash
python face_swap_client.py
```

### 2. 動態改變指定來源圖片 (動態 Source)
使用 `-s` 或 `--source` 參數指定不同的來源人臉：
```bash
python face_swap_client.py -s dynamic_source_face.jpg
```

### 3. 指定多張目標照片 (順序處理)
使用 `-t` 或 `--targets` 參數，您可以傳入多張照片路徑、整個資料夾、或是含有萬用字元的匹配模式：

*   **指定多張特定照片（按傳入順序處理）：**
    ```bash
    python face_swap_client.py -t target1.jpg target2.jpg target3.jpg
    ```
*   **指定一個資料夾（程式會自動讀取資料夾內所有圖片並按檔名排序）：**
    ```bash
    python face_swap_client.py -t ./my_targets
    ```
*   **使用萬用字元（Glob）：**
    ```bash
    python face_swap_client.py -t "targets/frame_*.png"
    ```
*   **同時動態指定 Source 與多張 Targets：**
    ```bash
    python face_swap_client.py -s face_a.jpg -t face_b.jpg face_c.jpg
    ```

### 4. 控制是否進行換臉 (--swap / -w)
使用 `-w` 或 `--swap` 參數來指定是否進行換臉。支援 `Y` (進行換臉) 與 `N` (不進行換臉，僅做圖檔格式化與雜湊值命名儲存，不連接 API 伺服器)：

*   **進行換臉（預設）：**
    ```bash
    python face_swap_client.py -w Y
    ```
*   **不進行換臉：**
    ```bash
    python face_swap_client.py -w N
    ```

### 5. 指定人臉增強融合比例 (--face-enhancer-blend)
使用 `--face-enhancer-blend` 參數來指定人臉增強（Face Enhancer）的融合比例，數值範圍為 0 到 100：
```bash
python face_swap_client.py --face-enhancer-blend 60
```
如果不指定，將優先採用 `appsettings.json` 中 `facefusion_settings` 的 `face_enhancer_blend` 設定值，若皆未指定則預設為 `60`。

### 6. 指定人臉選擇器與參考距離參數 (--face-selector-gender / --face-selector-race / --reference-face-distance / --hash-by-inputs)
使用以下參數來指定人臉選擇的篩選條件與相似度門檻，以及檔名雜湊模式：

*   **指定性別：** `--face-selector-gender {none,female,male}`
*   **指定種族：** `--face-selector-race {none,white,black,latino,asian,indian,arabic}`
*   **指定參考人臉相似度距離門檻 (0.0 到 1.0)：** `--reference-face-distance`
*   **啟用依輸入雜湊命名的機制：** `--hash-by-inputs {Y,N}` (若啟用，將依據「來源人臉 + 目標影像 + 換臉配置」計算出 100% 唯一的 Hash 檔名，避免 GPU 因運算微小誤差而對同一輸入產生不同 Hash)

例如：
```bash
python face_swap_client.py --face-selector-gender female --face-selector-race asian --reference-face-distance 0.2 --hash-by-inputs Y
```
如果不指定，將優先採用 `appsettings.json` 的設定值。

---

## 🔄 批次處理順序
當指定多個目標圖片時：
1. 程式只會對來源人臉圖片上傳一次（`/update`），提升執行效率。
2. 程式會依序上傳每一個 Target 檔案（`/update_1`）。
3. 發送執行換臉請求（`/run`）。
4. 獲取回應並轉為 100% 品質的 HEIC 位元組。
5. 根據 `hash_by_inputs` 設定，計算此張圖片（或其輸入組合與配置）的 Hash 值，最後儲存為 `{hash}.heic`。

---

## 💡 進階優化技巧：解決側臉與嘴形對齊問題

在進行臉部轉換時，**人物側面（側臉）**或**嘴部表情對齊不自然**是常見的痛點。您可以調整 [appsettings.json](file:///Users/shawnwang/Documents/agy/facefusion/appsettings.json) 中的 `facefusion_settings` 參數來改善。

### 1. 解決「人物側面（側臉）」偵測失敗或效果差
*   **調高參考臉部相似度門檻 (`reference_face_distance`)**：側臉的特徵與正臉差異較大。如果門檻太低（如預設的 `0.2`），系統會判斷側臉非同一人而跳過。建議調高至 `0.5` 到 `0.6`。
*   **調低臉部偵測評分門檻 (`face_detector_score`)**：側臉特徵不全時，偵測置信度會降低。將其調低（如從 `0.3` 降至 `0.15` 或 `0.2`）可以提高側臉被偵測到的機率。
*   **更改臉部選擇模式 (`face_selector_mode`)**：如果畫面中只有單一人臉，將其設為 `"one"`，不管相似度如何，只要偵測到人臉就直接替換。
*   **使用角度相似的 Source**：若目標是側臉，強行使用正臉作為 Source 會導致扭曲，提供角度類似的 Source 照片效果最佳。

### 2. 解決「嘴形無法對齊 / 嘴巴周圍不自然」
*   **啟用表情修復器 (`expression_restorer`)**：能把 Target 的嘴型、笑容等細微表情融合到換臉後的面部。
    *   在 `processors` 中加入 `"expression_restorer"`。
    *   可搭配調高阻尼因子 `"expression_restorer_factor"`（預設 `80`）。
*   **排除嘴部區域進行換臉 (直接保留 Target 原生嘴部)**：如果目標人物嘴形動作太大，直接不對嘴巴換臉往往更自然。
    *   在 `face_mask_regions` 中**移除** `"mouth"`, `"upper-lip"`, `"lower-lip"`。
*   **微調遮罩羽化與邊距 (Blur & Padding)**：
    *   調整 `"face_mask_blur"` (預設 `0.3`) 增加遮罩邊緣羽化融合度。
    *   調整 `"face_mask_padding"` (格式為 `[上, 右, 下, 左]`)，以解決側臉邊緣被切斷的問題。

