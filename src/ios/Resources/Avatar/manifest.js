window.SOULNEST_MANIFEST = {
  "schemaVersion": 1,
  "character": "yujie",
  "assetVersion": "1",
  "nameLocalized": { "zh-Hant": "語婕", "en": "Yujie" },
  "locale": "zh-Hant",
  "fallbackLocale": "en",
  "defaultOutfit": "casual",
  "outfits": {
    "casual": {
      "name": { "zh-Hant": "日常", "en": "Casual" },
      "accent": "#8b6cff",
      "defaultIdle": "idle_01",
      "fallbackTalking": "talk_soft",
      "states": {
        "idle_01":     { "src": "assets/videos/placeholder-idle.mp4",     "mode": "loop" },
        "idle_02":     { "src": "assets/videos/placeholder-idle.mp4",     "mode": "loop" },
        "thinking":    { "src": "assets/videos/placeholder-thinking.mp4", "mode": "loop" },
        "talk_soft":   { "src": "assets/videos/placeholder-talking.mp4",  "mode": "loop" },
        "talk_happy":  { "src": "assets/videos/placeholder-happy.mp4",    "mode": "loop" },
        "talk_excited":{ "src": "assets/videos/placeholder-excited.mp4",  "mode": "loop" },
        "shy":         { "src": "assets/videos/placeholder-shy.mp4",      "mode": "once", "fallback": "idle_01" },
        "sad":         { "src": "assets/videos/placeholder-sad.mp4",      "mode": "once", "fallback": "idle_01" },
        "angry":       { "src": "assets/videos/placeholder-angry.mp4",    "mode": "once", "fallback": "idle_01" },
        "caring":      { "src": "assets/videos/placeholder-talking.mp4",  "mode": "once", "fallback": "idle_01" }
      }
    },
    "office": {
      "name": { "zh-Hant": "辦公室", "en": "Office" },
      "accent": "#12c2a8",
      "defaultIdle": "idle_01",
      "fallbackTalking": "talk_soft",
      "states": {
        "idle_01":  { "src": "assets/videos/placeholder-idle.mp4",     "mode": "loop" },
        "thinking": { "src": "assets/videos/placeholder-thinking.mp4", "mode": "loop" },
        "talk_soft":{ "src": "assets/videos/placeholder-talking.mp4",  "mode": "loop" }
      }
    }
  },
  "labels": {
    "states": {
      "idle_01":      { "zh-Hant": "待機",   "en": "Idle" },
      "idle_02":      { "zh-Hant": "待機",   "en": "Idle" },
      "thinking":     { "zh-Hant": "思考中", "en": "Thinking" },
      "talk_soft":    { "zh-Hant": "說話中", "en": "Talking" },
      "talk_happy":   { "zh-Hant": "開心中", "en": "Talking happy" },
      "talk_excited": { "zh-Hant": "興奮中", "en": "Talking excited" },
      "shy":          { "zh-Hant": "害羞",   "en": "Shy" },
      "sad":          { "zh-Hant": "難過",   "en": "Sad" },
      "angry":        { "zh-Hant": "生氣",   "en": "Angry" },
      "caring":       { "zh-Hant": "關懷",   "en": "Caring" }
    },
    "inputPlaceholder": { "zh-Hant": "輸入訊息…", "en": "Type a message…" },
    "send":            { "zh-Hant": "送出", "en": "Send" },
    "mic":             { "zh-Hant": "語音輸入", "en": "Voice input" },
    "wardrobe":        { "zh-Hant": "衣櫃", "en": "Wardrobe" },
    "wardrobeTitle":   { "zh-Hant": "選擇造型", "en": "Choose an outfit" },
    "demo":            { "zh-Hant": "示範流程", "en": "Demo" },
    "fallbackClip":    { "zh-Hant": "預覽影片載入中…", "en": "Preview clip loading…" },
    "micComingSoon":   { "zh-Hant": "語音輸入將在後續版本推出。", "en": "Voice input is coming in a later version." },
    "cannedReply":     { "zh-Hant": "這是本機示範回覆，之後會由外部 Agent 回覆真正的答案。", "en": "This is a local demo reply. The external agent will answer for real later." }
  }
};
