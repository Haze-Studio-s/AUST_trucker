-- aurp_trucker — lang/locale.lua
-- Sistema unificado de tradução backend/frontend

Locales = Locales or {}

function _U(key, ...)
    local lang = (Config and (Config.lang or Config.locale)) or 'br'
    local dict = Locales[lang] or Locales['en'] or {}
    local str = dict[key] or key
    if select('#', ...) > 0 then
        local success, formatted = pcall(string.format, str, ...)
        if success then return formatted end
    end
    return str
end
