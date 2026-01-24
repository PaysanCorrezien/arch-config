// Shared helpers for provider modules.
// pragma keeps functions in a shared context for all imports.
.pragma library

function pick(settings, defaults, key, fallback) {
  if (settings && settings[key] !== undefined && settings[key] !== null) return settings[key]
  if (defaults && defaults[key] !== undefined && defaults[key] !== null) return defaults[key]
  return fallback
}

function calculateRemainingSec(resetsAt) {
  if (!resetsAt) return 0
  try {
    const resetTime = new Date(resetsAt).getTime()
    const now = Date.now()
    const remaining = Math.floor((resetTime - now) / 1000)
    return Math.max(0, remaining)
  } catch (e) {
    return 0
  }
}

function resetAtFromNow(seconds) {
  const safe = parseInt(seconds || 0, 10)
  if (!safe || safe <= 0) return ""
  const resetTime = new Date(Date.now() + safe * 1000)
  return resetTime.toISOString()
}

function shellQuote(value) {
  if (value === null || value === undefined) return "''"
  const text = String(value)
  return "'" + text.replace(/'/g, "'\"'\"'") + "'"
}

function clampPercent(value) {
  const pct = parseFloat(value || 0)
  if (isNaN(pct)) return 0
  return Math.max(0, Math.min(100, pct))
}
