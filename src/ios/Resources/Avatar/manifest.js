window.SOULNEST_MANIFEST = {
  "name": "SoulNest Avatar",
  "nameLocalized": { "zh-Hant": "玉潔", "en": "Yujie" },
  "version": "0.1.0",
  "locale": "zh-Hant",
  "fallbackLocale": "en",
  "defaultOutfit": "default",
  "defaultState": "idle",
  "states": {
    "idle":     { "clip": "assets/videos/placeholder-idle.mp4",     "loop": true },
    "thinking": { "clip": "assets/videos/placeholder-thinking.mp4", "loop": true },
    "talking":  { "clip": "assets/videos/placeholder-talking.mp4",  "loop": true },
    "happy":    { "clip": "assets/videos/placeholder-happy.mp4",    "loop": true },
    "shy":      { "clip": "assets/videos/placeholder-shy.mp4",      "loop": true },
    "sad":      { "clip": "assets/videos/placeholder-sad.mp4",      "loop": true },
    "angry":    { "clip": "assets/videos/placeholder-angry.mp4",    "loop": true },
    "excited":  { "clip": "assets/videos/placeholder-excited.mp4",  "loop": true }
  },
  "outfits": {
    "default": {
      "name": { "zh-Hant": "預設", "en": "Default" },
      "accent": "#8b6cff",
      "clips": {}
    },
    "night": {
      "name": { "zh-Hant": "夜嵐", "en": "Night" },
      "accent": "#12c2a8",
      "clips": {}
    }
  },
  "labels": {
    "statusIdle":     { "zh-Hant": "待機", "en": "Idle" },
    "statusThinking": { "zh-Hant": "思考中", "en": "Thinking" },
    "statusTalking":  { "zh-Hant": "說話中", "en": "Talking" },
    "statusHappy":    { "zh-Hant": "開心", "en": "Happy" },
    "statusShy":      { "zh-Hant": "害羞", "en": "Shy" },
    "statusSad":      { "zh-Hant": "難過", "en": "Sad" },
    "statusAngry":    { "zh-Hant": "生氣", "en": "Angry" },
    "statusExcited":  { "zh-Hant": "興奮", "en": "Excited" },
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
