# Telisten translation pass — entries for a native speaker to check

Camo, 13 November 2026. These were changed but the meaning in context is uncertain (no code context, or no settled term). Everything else in changes.json was a clear fix.

| Language | English key | Was | Now | Why unsure |
|---|---|---|---|---|
| ja | HTTPS chat-completions URL | HTTPS チャット補完 URL | HTTPS Chat Completions URL | Chat Completions is the OpenAI API name, not 'completion' in Japanese |
| ja | Hello again | こんにちは。 | おかえりなさい | こんにちは drops 'again'; welcome-back greeting (no code context) |
| ja | Latin-Hiragana | ラテン語-ひらがな | ラテン文字→ひらがな | Transliteration (Latin script to hiragana), not 'Latin language' |
| ja | Rounded | 丸い | ラウンド | 丸い is adjective; font design option |
| ja | Use an OpenAI-compatible endpoint supporting JSON chat completions. Generating s | JSON チャット補完をサポートする OpenAI 互換エンドポイントを使用します。生成すると歌詞テキストとプロンプトが | JSON 形式の Chat Completions に対応した OpenAI 互換エンドポイントを使用します。生成すると | Menu item name consistency; Chat Completions API name |
| zh-Hans | Code delivered by flash call | 通过 Flash Call 传递代码 | 已通过快速来电发送验证码 | Login code wording; flash-call delivery status |
| zh-Hans | Hello again | 再次你好 | 又见面了 | “再次你好” unnatural greeting |
| zh-Hans | Now playing section | 现在播放部分 | 正在播放页面 | Was “now-play part” |
| zh-Hans | On device | 在设备上 | 设备端 | Reading source option (on-device processing) |
| zh-Hans | Reading source | 阅读源码 | 读音来源 | Was “read source code” |
| zh-Hant | Code delivered by flash call | 透過 Flash Call 傳遞程式碼 | 已透過快速來電傳送驗證碼 | Login code, not program code |
| zh-Hant | Hello again | 再次你好 | 又見面了 | “再次你好” unnatural greeting |
| zh-Hant | Now playing section | 現在播放部分 | 正在播放頁面 | Was “now-play part” |
| zh-Hant | On device | 在設備上 | 裝置端 | Reading source option (on-device processing) |
| zh-Hant | Reading source | 閱讀原始碼 | 讀音來源 | Was “read source code” |
| ko | HTTPS chat-completions URL | HTTPS 채팅 완료 URL | HTTPS Chat Completions URL | API endpoint name, not "chat finished" |
| ko | Reading source | 읽기 소스 | 발음 소스 | Source of pronunciation readings (on-device vs LLM) |
| vi | Back to Now | Quay lại hiện tại | Quay lại vị trí hiện tại | Returns lyrics view to the current playing position |
| vi | Reading source | Nguồn đọc | Nguồn phát âm | Source of readings (on-device vs LLM), not 'source to read' |
| vi | Text opacity | Độ mờ văn bản | Độ mờ đục của văn bản | 'Độ mờ' reads as blur/transparency; opacity is the opposite |
| fr | Back to Now | Revenir au présent | Revenir à la ligne actuelle | 'Revenir au présent' is odd; button returns lyrics view to the currently playing line |
| fr | Now playing section | Section en cours de lecture | Section À l'écoute | Now Playing = À l'écoute (Apple fr); picker for sections of Now Playing screen |
| fr | Reading source | Source de lecture | Source de la prononciation | 'reading' = phonetic reading for pronunciation, not playback/reading source |
| es | Latin-Hiragana | Latín-Hiragana | Latino-Hiragana | Latin here is the Latin script (latino), not the Latin language (latín) |
| es | Now playing section | Sección en reproducción | Sección de En reproducción | picker for sections of the Now Playing screen |
| es | Reading source | fuente de lectura | Fuente de pronunciación | UI label must start with a capital; 'reading' = phonetic reading for pronunciation |

Also worth a native look: Korean uses "Telegram" instead of 텔레그램 throughout; Spanish now uses tú (Apple's register) instead of usted; French uses "playlist" (Apple Music's term).
