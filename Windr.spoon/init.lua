--- === Windr ===
---
--- Gestionnaire visuel de dispositions de fenêtres (layouts) pour macOS.
---
--- * Icône dans la barre de menus + panneau listant les profils, avec aperçu de chaque disposition
--- * Clic sur une carte (ou 1-9 / flèches + Entrée) pour appliquer un profil
--- * « Capturer » (N) enregistre la disposition actuelle des fenêtres comme nouveau profil
--- * Modifier, remplacer, supprimer et réordonner (glisser-déposer) les profils
---
--- Les profils capturés sont enregistrés dans ~/.hammerspoon/windr_layouts.json.
---
--- Utilisation minimale dans ~/.hammerspoon/init.lua :
---   hs.loadSpoon("Windr")
---   spoon.Windr:start()

local obj = {}
obj.__index = obj

obj.name = "Windr"
obj.version = "1.0"
obj.author = "jc.suzanne"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local M = obj

local CARD_W, GAP, PAD = 196, 10, 16

local config = {
  -- Raccourci global pour ouvrir/fermer le panneau (false pour désactiver)
  hotkey = { { "cmd", "alt", "ctrl" }, "space" },
  -- Modificateurs pour appliquer le profil n°1..9 du panneau (ex. {"cmd","alt","ctrl"}), nil = désactivé
  profileHotkeys = nil,
  -- Profils de départ : { nom = { [largeurEcran] = { App = {x, y, w, h} }, default = {...} } }
  layouts = {},
  -- Fichier des profils capturés
  profilesFile = hs.configdir .. "/windr_layouts.json",
  -- Bundle IDs supplémentaires à ne jamais capturer
  ignore = {},
}

-- Apps jamais capturées (fenêtres utilitaires souvent ouvertes par hasard), par bundle ID
local IGNORED = {
  ["org.hammerspoon.Hammerspoon"] = true,
  ["com.apple.finder"] = true,
  ["com.apple.systempreferences"] = true,
}

local layoutsRef = {}
local menu, panel, usercontent, toggleHotkey
local profileHotkeys = {}
local previousWin, pending
local lastHide = 0
local iconCache = {}
local custom, builtin = {}, {}
local timers = {}

M.current = hs.settings.get("windr.current")

local function setCurrent(name)
  M.current = name
  hs.settings.set("windr.current", name)
end

-- ---------- Profils capturés (JSON) ----------
local function loadCustom()
  local f = io.open(config.profilesFile, "r")
  if not f then return {} end
  local ok, data = pcall(hs.json.decode, f:read("a"))
  f:close()
  if not ok or type(data) ~= "table" then
    hs.alert.show("Windr : " .. config.profilesFile .. " illisible")
    return {}
  end
  -- Les clés JSON sont des chaînes : "3840" -> 3840
  local out = {}
  for name, set in pairs(data) do
    out[name] = {}
    for k, rect in pairs(set) do out[name][tonumber(k) or k] = rect end
  end
  return out
end

local function writeCustom()
  local out = {}
  for name, set in pairs(custom) do
    out[name] = {}
    for k, rect in pairs(set) do out[name][tostring(k)] = rect end
  end
  local f = io.open(config.profilesFile, "w")
  f:write(next(out) and hs.json.encode(out, true) or "{}")
  f:close()
end

-- Profils affichés = profils de départ, avec les profils capturés par-dessus
local function rebuild()
  for name in pairs(layoutsRef) do layoutsRef[name] = nil end
  for name, set in pairs(config.layouts) do
    layoutsRef[name] = {}
    for k, rect in pairs(set) do layoutsRef[name][k] = rect end
  end
  for name, set in pairs(custom) do
    layoutsRef[name] = layoutsRef[name] or {}
    for k, rect in pairs(set) do layoutsRef[name][k] = rect end
  end
end

-- ---------- Ordre des profils ----------
local function orderedNames()
  local rank = {}
  for i, name in ipairs(hs.settings.get("windr.order") or {}) do rank[name] = i end
  local names = {}
  for name in pairs(layoutsRef) do names[#names + 1] = name end
  table.sort(names, function(a, b)
    local ra, rb = rank[a] or math.huge, rank[b] or math.huge
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  return names
end

local function renameInOrder(from, to)
  local order = hs.settings.get("windr.order") or {}
  for i, n in ipairs(order) do if n == from then order[i] = to end end
  hs.settings.set("windr.order", order)
end

-- ⌘⌥⌃1..9 (ou les modificateurs choisis) suivent l'ordre du panneau
local function bindProfileHotkeys()
  for _, hk in ipairs(profileHotkeys) do hk:delete() end
  profileHotkeys = {}
  if not config.profileHotkeys then return end
  for i, name in ipairs(orderedNames()) do
    if i > 9 then break end
    profileHotkeys[#profileHotkeys + 1] = hs.hotkey.bind(config.profileHotkeys, tostring(i), function() M:apply(name) end)
  end
end

-- ---------- Application d'un profil ----------
--- Windr:apply(name)
--- Method
--- Applique le profil `name` sur l'écran principal (variante de la largeur d'écran, sinon "default").
function M:apply(name)
  local set = layoutsRef[name]
  if not set then
    hs.alert.show("Layout inconnu : " .. tostring(name))
    return
  end
  local screen = hs.screen.mainScreen()
  local layout = set[math.floor(screen:fullFrame().w)] or set.default or {}
  for appName, r in pairs(layout) do
    local app = hs.application.get(appName)
    if app then
      for _, win in ipairs(app:allWindows()) do
        if win:isStandard() then
          win:moveToScreen(screen)
          win:moveToUnit(hs.geometry.rect(r[1], r[2], r[3], r[4]))
        end
      end
    end
  end
  setCurrent(name)
  hs.alert.show("Layout " .. name)
end

-- ---------- Icônes d'apps (data URL, en cache) ----------
local function iconFor(appName)
  if iconCache[appName] ~= nil then return iconCache[appName] end
  local path
  local app = hs.application.get(appName)
  if app then path = app:path() end
  if not path then
    local guess = "/Applications/" .. appName .. ".app"
    if hs.fs.attributes(guess) then path = guess end
  end
  if not path then
    -- Nom localisé (« Réglages Système » -> System Settings.app) : Spotlight connaît le nom affiché
    local query = string.format("kMDItemContentType == 'com.apple.application-bundle' && kMDItemDisplayName == '%s'",
                                (appName:gsub("'", "\\'")))
    local out = hs.execute("mdfind " .. string.format("%q", query) .. " | head -1")
    path = out and out:match("^(.-)%s*$")
    if path == "" then path = nil end
  end
  local url = false
  if path then
    local img = hs.image.iconForFile(path)
    if img then url = img:setSize({ w = 64, h = 64 }):encodeAsURLString() end
  end
  iconCache[appName] = url
  return url
end

-- ---------- Capture de la disposition actuelle ----------
local function r3(v) return math.floor(math.max(0, math.min(1, v)) * 1000 + 0.5) / 1000 end

-- Une fenêtre par app (la plus en avant), sur l'écran principal, en fractions de screen:frame()
-- comme moveToUnit dans Windr:apply.
local function captureCurrent()
  local screen = hs.screen.mainScreen()
  local sf = screen:frame()
  local rects, order, seen = {}, {}, {}
  for _, win in ipairs(hs.window.orderedWindows()) do
    local app = win:application()
    local name = app and app:name()
    if name and not seen[name] and not IGNORED[app:bundleID() or ""] and win:isStandard()
       and win:screen() and win:screen():id() == screen:id() then
      seen[name] = true
      order[#order + 1] = name
      local f = win:frame()
      rects[name] = { r3((f.x - sf.x) / sf.w), r3((f.y - sf.y) / sf.h), r3(f.w / sf.w), r3(f.h / sf.h) }
    end
  end
  return { key = math.floor(screen:fullFrame().w), rects = rects, order = order }
end

local function normalizeName(name)
  return (tostring(name or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "-"):gsub("[^%w_-]", ""):gsub("%-%-+", "-"))
end

-- Enregistre `snapshot` sous `name` pour la largeur d'écran capturée.
-- Un nouveau profil sert aussi de "default" pour les autres écrans.
local function saveProfile(name, snapshot)
  name = normalizeName(name)
  if name == "" or not next(snapshot.rects) then return false end
  custom[name] = custom[name] or {}
  custom[name][snapshot.key] = snapshot.rects
  local merged = layoutsRef[name]
  if not (merged and merged.default) and not custom[name].default then
    custom[name].default = snapshot.rects
  end
  writeCustom()
  setCurrent(name)
  return name
end

-- Édition : retire `excluded` de toutes les variantes de `from`, et renomme si `name` diffère
local function editProfile(from, name, excluded)
  name = normalizeName(name)
  local src = layoutsRef[from]
  if name == "" or not src then return false end
  local drop = {}
  for _, appName in ipairs(excluded or {}) do drop[appName] = true end

  local edited = {}
  for k, rects in pairs(src) do
    local kept = {}
    for appName, r in pairs(rects) do
      if not drop[appName] then kept[appName] = r end
    end
    if next(kept) then edited[k] = kept end
  end
  if not next(edited) then return false end

  if name ~= from and custom[from] and not builtin[from] then
    custom[from] = nil
    renameInOrder(from, name)
  end
  custom[name] = custom[name] or {}
  for k, rects in pairs(edited) do custom[name][k] = rects end
  writeCustom()
  setCurrent(name)
  return name
end

--- Windr:save(name)
--- Method
--- Enregistre la disposition actuelle sous `name` (ex. hs -c 'spoon.Windr:save("dev")').
function M:save(name)
  local saved = saveProfile(name, captureCurrent())
  if saved then
    rebuild()
    bindProfileHotkeys()
    hs.alert.show("Profil « " .. saved .. " » enregistré")
  end
  return saved
end

-- ---------- Données envoyées au panneau ----------
local function toApps(layout, order)
  local apps = {}
  local names = order
  if not names then
    names = {}
    for appName in pairs(layout) do names[#names + 1] = appName end
  end
  for _, appName in ipairs(names) do
    local r = layout[appName]
    apps[#apps + 1] = {
      name = appName, x = r[1], y = r[2], w = r[3], h = r[4],
      running = hs.application.get(appName) ~= nil,
      icon = iconFor(appName) or nil,
    }
  end
  if not order then
    table.sort(apps, function(a, b) return a.x == b.x and a.y < b.y or a.x < b.x end)
  end
  return apps
end

local function columns(cards) return cards <= 4 and 2 or 3 end

local function buildData()
  local screen = hs.screen.mainScreen()
  local full, sf = screen:fullFrame(), screen:frame()
  local key = math.floor(full.w)

  local profiles = {}
  for _, name in ipairs(orderedNames()) do
    local set = layoutsRef[name]
    profiles[#profiles + 1] = {
      name = name,
      variant = set[key] and tostring(key) or "default",
      apps = toApps(set[key] or set.default or {}),
      custom = custom[name] ~= nil,
      builtin = builtin[name] == true,
    }
  end

  pending = captureCurrent()
  local backToFront = {}
  for i = #pending.order, 1, -1 do backToFront[#backToFront + 1] = pending.order[i] end
  local cols = columns(#profiles + 1)

  return {
    screen = { name = screen:name(), w = sf.w, h = sf.h, key = tostring(key),
               label = math.floor(full.w) .. " × " .. math.floor(full.h) },
    current = M.current,
    cols = cols, cardW = CARD_W, gap = GAP,
    contentW = cols * CARD_W + (cols - 1) * GAP,
    profiles = profiles,
    -- arrière -> avant, pour que la fenêtre au premier plan soit peinte en dernier
    capture = toApps(pending.rects, backToFront),
  }
end

-- ---------- HTML ----------
local HTML_HEAD = [==[
<!doctype html><html><head><meta charset="utf-8"><style>
:root {
  --bg: rgba(250,250,252,.97); --fg: #0f0f12; --muted: rgba(60,60,67,.62); --faint: rgba(60,60,67,.35);
  --line: rgba(0,0,0,.07); --card: rgba(0,0,0,.025); --card-hover: rgba(0,0,0,.05);
  --screen: linear-gradient(155deg, #eceef4 0%, #e0e4ed 100%);
  --tile: #fbfbfd; --tile-line: rgba(0,0,0,.07); --tile-shadow: 0 1px 2px rgba(0,0,0,.08), 0 2px 8px rgba(0,0,0,.06);
  --kbd: rgba(0,0,0,.05); --accent: #0a84ff; --accent-soft: rgba(10,132,255,.16);
  --danger: #ff3b30; --input: rgba(0,0,0,.04); --highlight: rgba(255,255,255,.7);
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: rgba(23,23,26,.97); --fg: #f5f5f7; --muted: rgba(235,235,245,.56); --faint: rgba(235,235,245,.28);
    --line: rgba(255,255,255,.08); --card: rgba(255,255,255,.025); --card-hover: rgba(255,255,255,.055);
    --screen: linear-gradient(155deg, #2a2a31 0%, #1c1c21 100%);
    --tile: #323238; --tile-line: rgba(255,255,255,.1); --tile-shadow: 0 1px 3px rgba(0,0,0,.4), 0 3px 10px rgba(0,0,0,.3);
    --kbd: rgba(255,255,255,.07); --accent: #0a84ff; --accent-soft: rgba(10,132,255,.22);
    --danger: #ff453a; --input: rgba(255,255,255,.05); --highlight: rgba(255,255,255,.06);
  }
}
* { box-sizing: border-box; margin: 0; padding: 0; }
html { background: transparent; }
body {
  font: 13px/1.3 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; color: var(--fg);
  background: var(--bg); border: 1px solid var(--line); border-radius: 14px;
  box-shadow: inset 0 1px 0 var(--highlight);
  padding: 16px; overflow: hidden; cursor: default;
  -webkit-user-select: none; -webkit-font-smoothing: antialiased;
}
#app { animation: in .2s cubic-bezier(.2,.8,.2,1); }
@keyframes in { from { opacity: 0; transform: translateY(-4px) scale(.985); } }
button { font: inherit; color: inherit; background: none; border: 0; cursor: default; }
svg { display: block; fill: none; stroke: currentColor; stroke-width: 1.6; stroke-linecap: round; stroke-linejoin: round; }

header { display: flex; align-items: center; justify-content: space-between; margin: 0 2px 14px; }
h1 { font-size: 14px; font-weight: 650; letter-spacing: -.01em; }
header p { font-size: 11px; color: var(--muted); margin-top: 1px; }
.chip { font-size: 10.5px; font-weight: 500; color: var(--muted); background: var(--kbd);
        border-radius: 999px; padding: 3px 9px; }

.grid { display: grid; }
.card { position: relative; padding: 6px; border-radius: 12px; background: var(--card);
        box-shadow: 0 0 0 1px var(--line); transition: background .15s, box-shadow .15s, transform .15s; }
.card.sel { background: var(--card-hover); box-shadow: 0 0 0 1.5px var(--accent), 0 0 0 5px var(--accent-soft); }
.card:active { transform: scale(.985); }
.card.dragging { z-index: 2; background: var(--card-hover);
                 box-shadow: 0 0 0 1.5px var(--accent), 0 12px 32px rgba(0,0,0,.35); }
.card.dragging:active { transform: none; }
body.is-dragging, body.is-dragging * { cursor: grabbing !important; }
body.is-dragging .actions { display: none; }
kbd:empty { display: none; }

.screen { position: relative; border-radius: 7px; background: var(--screen); overflow: hidden;
          box-shadow: inset 0 0 0 1px var(--line); }
.win { position: absolute; padding: 1.5px; }
.tile { width: 100%; height: 100%; border-radius: 4px; background: var(--tile);
        box-shadow: inset 0 0 0 1px var(--tile-line), var(--tile-shadow);
        display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px;
        overflow: hidden; transition: background .15s; }
.card.sel .tile { background: color-mix(in srgb, var(--tile), var(--accent) 10%); }
.icons { display: flex; gap: 3px; }
.tile.covered { justify-content: flex-start; align-items: flex-start; padding: 4px; }
.tile.covered img { width: 14px; height: 14px; }
.tile img { width: 20px; height: 20px; filter: drop-shadow(0 1px 1.5px rgba(0,0,0,.25)); }
.big .tile img { width: 30px; height: 30px; }
.tile span { font-size: 9.5px; font-weight: 500; color: var(--muted); max-width: 92%;
             white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.big .tile span { font-size: 11px; }
.win.off .tile { opacity: .5; }
.apps { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 12px; }
.app { display: inline-flex; align-items: center; gap: 6px; height: 28px; padding: 0 8px 0 6px;
       border-radius: 8px; background: var(--kbd); box-shadow: inset 0 0 0 1px var(--line);
       font-size: 12px; font-weight: 500; transition: opacity .12s, background .12s; }
.app img { width: 18px; height: 18px; }
.app svg { width: 11px; height: 11px; color: var(--faint); }
.app:hover svg { color: var(--fg); }
.app.excluded { opacity: .45; background: transparent; }
.app.excluded span { text-decoration: line-through; }
.win.off img { filter: grayscale(1); }

.actions { position: absolute; top: 5px; right: 5px; display: flex; gap: 4px;
           opacity: 0; transform: translateY(-2px); transition: opacity .12s, transform .12s; }
.card:hover .actions, .actions:has(.confirm) { opacity: 1; transform: none; }
.act { height: 22px; min-width: 22px; padding: 0 5px; border-radius: 6px; display: flex; align-items: center;
       justify-content: center; gap: 4px; font-size: 10.5px; font-weight: 600;
       background: var(--bg); box-shadow: 0 0 0 1px var(--line), 0 2px 6px rgba(0,0,0,.18); color: var(--muted); }
.act svg { width: 12px; height: 12px; }
.act:hover { color: var(--fg); }
.act.danger:hover, .act.confirm { color: #fff; background: var(--danger); box-shadow: none; }

.meta { display: flex; align-items: center; gap: 8px; padding: 9px 4px 3px; }
.meta .txt { flex: 1; min-width: 0; }
.name { font-weight: 600; letter-spacing: -.01em; display: flex; align-items: center; gap: 6px;
        white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sub { font-size: 11px; color: var(--muted); margin-top: 1px; }
.dot { width: 6px; height: 6px; border-radius: 50%; background: #30d158; box-shadow: 0 0 0 3px rgba(48,209,88,.18); }
kbd { font: 600 10px ui-monospace, "SF Mono", monospace; color: var(--muted); background: var(--kbd);
      border-radius: 5px; min-width: 18px; height: 18px; padding: 0 5px;
      display: inline-flex; align-items: center; justify-content: center; }

.new .screen { background: transparent; box-shadow: none; outline: 1.5px dashed var(--faint); outline-offset: -1.5px;
               display: flex; align-items: center; justify-content: center; flex-direction: column; gap: 6px;
               color: var(--muted); font-size: 11px; font-weight: 500; transition: color .15s, outline-color .15s; }
.new .screen svg { width: 20px; height: 20px; }
.new.sel .screen { color: var(--accent); outline-color: var(--accent); }

footer { display: flex; flex-wrap: wrap; gap: 6px 14px; margin: 14px 2px 0; font-size: 11px; color: var(--faint); }
footer span { display: inline-flex; align-items: center; gap: 5px; white-space: nowrap; }
footer kbd { color: var(--faint); }

.big { border-radius: 10px; }
.none { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
        color: var(--muted); font-size: 12px; }
.form { display: flex; gap: 8px; margin-top: 14px; }
input { flex: 1; font: 500 13px -apple-system, sans-serif; color: var(--fg); background: var(--input);
        border: 0; border-radius: 8px; padding: 0 11px; height: 32px; outline: none;
        box-shadow: inset 0 0 0 1px var(--line); transition: box-shadow .15s; -webkit-user-select: text; }
input:focus { box-shadow: inset 0 0 0 1px var(--accent), 0 0 0 4px var(--accent-soft); }
input::placeholder { color: var(--faint); }
.btn { height: 32px; padding: 0 14px; border-radius: 8px; font-weight: 600; }
.btn.ghost { color: var(--muted); }
.btn.ghost:hover { background: var(--kbd); color: var(--fg); }
.btn.primary { background: var(--accent); color: #fff; box-shadow: inset 0 1px 0 rgba(255,255,255,.2); }
.btn.primary:disabled { opacity: .4; }
.hint { font-size: 11px; color: var(--muted); margin: 9px 2px 0; min-height: 14px; }
.hint b { color: var(--fg); font-weight: 600; }
</style></head><body><div id="app"></div><script>
const D = ]==]

local HTML_TAIL = [==[;
const post = m => webkit.messageHandlers.windr.postMessage(m);
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const profiles = Object.values(D.profiles || {});
const capture = Object.values(D.capture || {});
const ratio = D.screen.h / D.screen.w;
const innerW = D.cardW - 12;
const ICON = {
  frame: '<svg viewBox="0 0 16 16"><path d="M2 5.5v-2A1.5 1.5 0 0 1 3.5 2h2M10.5 2h2A1.5 1.5 0 0 1 14 3.5v2M14 10.5v2a1.5 1.5 0 0 1-1.5 1.5h-2M5.5 14h-2A1.5 1.5 0 0 1 2 12.5v-2"/><rect x="5" y="5" width="6" height="6" rx="1"/></svg>',
  x: '<svg viewBox="0 0 16 16"><path d="M4.5 4.5l7 7M11.5 4.5l-7 7"/></svg>',
  plus: '<svg viewBox="0 0 16 16"><path d="M8 3.5v9M3.5 8h9"/></svg>',
  edit: '<svg viewBox="0 0 16 16"><path d="M10.5 2.5l3 3L6 13H3v-3z"/><path d="M9 4l3 3"/></svg>',
};
const app = document.getElementById('app');
let view = 'grid', confirmDel = -1, target = null;
const excluded = new Set();
let sel = Math.max(0, profiles.findIndex(p => p.name === D.current));

const fit = () => requestAnimationFrame(() => post({ type: 'size', h: document.body.offsetHeight }));
const normalize = s => s.trim().toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9_-]/g, '').replace(/-{2,}/g, '-');

// Profils enregistrés : une tuile par emplacement (apps superposées regroupées),
// les plus grandes dessinées d'abord pour que les petites restent visibles.
function grouped(apps) {
  const slots = new Map();
  for (const a of apps) {
    const key = [a.x, a.y, a.w, a.h].map(v => Math.round(v * 100)).join(',');
    if (!slots.has(key)) slots.set(key, { ...a, members: [] });
    slots.get(key).members.push(a);
  }
  return [...slots.values()].sort((a, b) => b.w * b.h - a.w * a.h);
}

function tiles(apps, width) {
  const height = width * ratio;
  const slots = grouped(apps);
  // Une fenêtre recouverte par une autre affiche ses icônes en haut à gauche, sans nom
  const covers = (o, s) => o !== s && o.x < s.x + s.w / 2 && o.x + o.w > s.x + s.w / 2
                                    && o.y < s.y + s.h / 2 && o.y + o.h > s.y + s.h / 2;
  return slots.map((s, i) => {
    const covered = slots.slice(i + 1).some(o => covers(o, s));
    const pw = s.w * width, ph = s.h * height;
    const names = s.members.map(m => m.name);
    const withIcon = s.members.filter(m => m.icon);
    const maxIcons = Math.max(1, Math.floor((pw - 6) / 24));
    const icon = withIcon.length && pw >= 24 && ph >= 24;
    const label = !covered && (!icon || (pw >= 54 && ph >= 52));
    const running = s.members.some(m => m.running);
    const cls = running ? '' : ' off';
    const title = s.members.map(m => m.name + (m.running ? '' : ' (fermée)')).join(' + ');
    return `<div class="win${cls}" data-app="${esc(s.name)}" title="${esc(title)}"
      style="left:${s.x * 100}%;top:${s.y * 100}%;width:${s.w * 100}%;height:${s.h * 100}%">
      <div class="tile${covered ? ' covered' : ''}">${icon ? `<div class="icons">${withIcon.slice(0, maxIcons).map(m => `<img src="${m.icon}">`).join('')}</div>` : ''}
      ${label ? `<span>${esc(names.join(' + '))}</span>` : ''}</div></div>`;
  }).join('');
}

function card(p, i) {
  const apps = Object.values(p.apps || {});
  const current = p.name === D.current;
  const del = p.custom ? `<button class="act danger${confirmDel === i ? ' confirm' : ''}" data-act="delete"
      title="${p.builtin ? 'Rétablir la version d’origine' : 'Supprimer'}">${ICON.x}${confirmDel === i ? (p.builtin ? 'Rétablir ?' : 'Supprimer ?') : ''}</button>` : '';
  return `<div class="card" data-i="${i}">
    <div class="screen" style="height:${Math.round(innerW * ratio)}px">${tiles(apps, innerW)}
      <div class="actions"><button class="act" data-act="edit" title="Modifier les apps du profil">${ICON.edit}</button><button class="act" data-act="update" title="Remplacer par la disposition actuelle">${ICON.frame}</button>${del}</div>
    </div>
    <div class="meta"><div class="txt">
      <div class="name">${esc(p.name)}${current ? '<i class="dot" title="Actif"></i>' : ''}</div>
      <div class="sub">${apps.length} app${apps.length > 1 ? 's' : ''} · ${p.variant}</div>
    </div><kbd class="num">${i < 9 ? i + 1 : ''}</kbd></div>
  </div>`;
}

function renderGrid() {
  view = 'grid';
  app.innerHTML = `
    <header><div><h1>Layouts</h1><p>${esc(D.screen.name)}</p></div><span class="chip">${D.screen.label}</span></header>
    <div class="grid" style="grid-template-columns:repeat(${D.cols}, ${D.cardW}px);gap:${D.gap}px">
      ${profiles.map(card).join('')}
      <div class="card new" data-i="${profiles.length}">
        <div class="screen" style="height:${Math.round(innerW * ratio)}px">${ICON.frame}Capturer</div>
        <div class="meta"><div class="txt"><div class="name">Nouveau profil</div>
          <div class="sub">Disposition actuelle</div></div><kbd>N</kbd></div>
      </div>
    </div>
    <footer><span><kbd>1</kbd>–<kbd>9</kbd> appliquer</span><span><kbd>N</kbd> capturer</span><span>glisser pour réordonner</span><span><kbd>esc</kbd> fermer</span></footer>`;
  select(sel);
  fit();
}

// Éditeur : mode 'capture' (disposition actuelle) ou 'edit' (apps déjà enregistrées du profil)
let editMode = 'capture', editFrom = null, editApps = [];

function renderEditor(mode, name) {
  view = 'editor';
  editMode = mode;
  editFrom = name;
  excluded.clear();
  const p = profiles.find(q => q.name === name);
  editApps = mode === 'edit' ? Object.values(p.apps || {}) : capture;
  const W = D.contentW;
  const title = mode === 'edit' ? `Modifier « ${esc(name)} »` : name ? `Remplacer « ${esc(name)} »` : 'Nouveau profil';
  const sub = mode === 'edit' ? `Variante ${p.variant} · clique sur une app pour la retirer`
    : `Disposition actuelle · clique sur une app pour l’exclure`;
  app.innerHTML = `
    <header><div><h1>${title}</h1><p>${sub}</p></div><span class="chip">${D.screen.label}</span></header>
    <div class="screen big" id="preview" style="height:${Math.round(W * ratio)}px"></div>
    <div class="apps" id="apps"></div>
    <div class="form">
      <input id="name" placeholder="Nom du profil" value="${esc(name || '')}" spellcheck="false" autocomplete="off">
      <button class="btn ghost" data-cancel>Annuler</button>
      <button class="btn primary" data-save>Enregistrer</button>
    </div>
    <p class="hint" id="hint"></p>`;
  const input = document.getElementById('name');
  input.addEventListener('input', updateHint);
  refreshEditor();
  input.focus();
  input.select();
}

function refreshEditor() {
  const kept = editApps.filter(a => !excluded.has(a.name));
  document.getElementById('preview').innerHTML = kept.length ? tiles(kept, D.contentW)
    : `<div class="none">${editApps.length ? 'Aucune app conservée' : 'Aucune fenêtre visible sur cet écran'}</div>`;
  document.getElementById('apps').innerHTML = editApps.map(a => `
    <button class="app${excluded.has(a.name) ? ' excluded' : ''}" data-app="${esc(a.name)}">
      ${a.icon ? `<img src="${a.icon}">` : ''}<span>${esc(a.name)}</span>${excluded.has(a.name) ? ICON.plus : ICON.x}</button>`).join('');
  updateHint();
  fit();
}

function updateHint() {
  const name = normalize(document.getElementById('name').value);
  const exists = profiles.find(p => p.name === name);
  const kept = editApps.length - excluded.size;
  document.querySelector('[data-save]').disabled = !name || !kept;
  const hint = document.getElementById('hint');
  if (!name) { hint.innerHTML = 'Lettres, chiffres, - et _'; return; }
  if (editMode === 'edit') {
    const from = profiles.find(p => p.name === editFrom);
    const removed = excluded.size ? `Retire ${[...excluded].map(n => `<b>${esc(n)}</b>`).join(', ')} de toutes les variantes` : 'Aucun changement d’apps';
    hint.innerHTML = name === editFrom ? removed
      : from.custom && !from.builtin ? `${removed} · renomme en <b>${esc(name)}</b>`
      : `${removed} · enregistre une copie <b>${esc(name)}</b>`;
    return;
  }
  hint.innerHTML = exists ? `Remplace la variante <b>${D.screen.key}</b> de <b>${esc(name)}</b>`
    : `Crée <b>${esc(name)}</b> pour cet écran (${D.screen.key}) et par défaut ailleurs`;
}

function save() {
  const name = normalize(document.getElementById('name').value);
  if (name && editApps.length > excluded.size) {
    post({ type: 'save', name, excluded: [...excluded], from: editMode === 'edit' ? editFrom : null });
  }
}

function select(i) {
  sel = i;
  document.querySelectorAll('.card').forEach((c, j) => c.classList.toggle('sel', j === i));
}

function activate(i) {
  if (i === profiles.length) renderEditor('capture', null);
  else post({ type: 'apply', name: profiles[i].name });
}

document.addEventListener('mouseover', e => {
  const c = e.target.closest('.card');
  if (c && view === 'grid' && +c.dataset.i !== sel) select(+c.dataset.i);
});

document.addEventListener('click', e => {
  if (justDragged) return;
  if (view === 'editor') {
    const chip = e.target.closest('.app');
    if (chip) {
      const n = chip.dataset.app;
      excluded.has(n) ? excluded.delete(n) : excluded.add(n);
      refreshEditor();
      return document.getElementById('name').focus();
    }
    if (e.target.closest('[data-cancel]')) renderGrid();
    if (e.target.closest('[data-save]')) save();
    return;
  }
  const act = e.target.closest('[data-act]');
  const c = e.target.closest('.card');
  if (act) {
    const i = +c.dataset.i;
    if (act.dataset.act === 'edit') return renderEditor('edit', profiles[i].name);
    if (act.dataset.act === 'update') return renderEditor('capture', profiles[i].name);
    if (confirmDel === i) return post({ type: 'delete', name: profiles[i].name });
    confirmDel = i;
    return renderGrid();
  }
  if (confirmDel >= 0) { confirmDel = -1; renderGrid(); }
  if (c) activate(+c.dataset.i);
});

document.addEventListener('keydown', e => {
  if (view === 'editor') {
    if (e.key === 'Escape') { e.preventDefault(); renderGrid(); }
    if (e.key === 'Enter') { e.preventDefault(); save(); }
    return;
  }
  const n = profiles.length + 1;
  if (e.key === 'Escape') return confirmDel >= 0 ? (confirmDel = -1, renderGrid()) : post({ type: 'close' });
  if (e.key === 'Enter') return activate(sel);
  if (e.key === 'n' || e.key === 'N') { e.preventDefault(); return renderEditor('capture', null); }
  if (/^[1-9]$/.test(e.key) && +e.key <= profiles.length) return activate(+e.key - 1);
  const moves = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: D.cols, ArrowUp: -D.cols };
  if (moves[e.key]) { e.preventDefault(); select((sel + moves[e.key] + n) % n); }
});

// ---------- Glisser-déposer pour réordonner ----------
let drag = null, justDragged = false;
const profileCards = () => [...document.querySelectorAll('.card:not(.new)')];

// Anime les cartes de leur ancienne position vers la nouvelle (FLIP)
function flip(mutate) {
  const els = [...document.querySelectorAll('.card')];
  const before = new Map(els.map(el => [el, el.getBoundingClientRect()]));
  mutate();
  for (const el of els) {
    const a = before.get(el), b = el.getBoundingClientRect();
    const dx = a.left - b.left, dy = a.top - b.top;
    if (!dx && !dy) continue;
    el.style.transition = 'none';
    el.style.transform = `translate(${dx}px, ${dy}px)`;
    requestAnimationFrame(() => {
      el.style.transition = 'transform .18s cubic-bezier(.2,.8,.2,1)';
      el.style.transform = '';
    });
  }
  profileCards().forEach((c, i) => { c.querySelector('.num').textContent = i < 9 ? i + 1 : ''; });
  drag.lockUntil = performance.now() + 190;
}

document.addEventListener('mousedown', e => {
  if (view !== 'grid' || e.button !== 0 || e.target.closest('[data-act]')) return;
  const c = e.target.closest('.card:not(.new)');
  if (c) drag = { el: c, x: e.clientX, y: e.clientY, active: false, lockUntil: 0 };
});

document.addEventListener('mousemove', e => {
  if (!drag) return;
  if (!drag.active) {
    if (Math.hypot(e.clientX - drag.x, e.clientY - drag.y) < 5) return;
    drag.active = true;
    drag.el.classList.add('dragging');
    document.body.classList.add('is-dragging');
  }
  if (performance.now() < drag.lockUntil) return;
  const over = document.elementFromPoint(e.clientX, e.clientY)?.closest('.card:not(.new)');
  if (!over || over === drag.el) return;
  const cards = profileCards();
  const forward = cards.indexOf(drag.el) < cards.indexOf(over);
  flip(() => over.parentNode.insertBefore(drag.el, forward ? over.nextSibling : over));
});

document.addEventListener('mouseup', () => {
  if (!drag) return;
  if (drag.active) {
    const moved = profiles[+drag.el.dataset.i];
    const reordered = profileCards().map(c => profiles[+c.dataset.i]);
    profiles.splice(0, profiles.length, ...reordered);
    post({ type: 'order', names: profiles.map(p => p.name) });
    document.body.classList.remove('is-dragging');
    sel = profiles.indexOf(moved);
    confirmDel = -1;
    justDragged = true;
    setTimeout(() => { justDragged = false; }, 0);
    renderGrid();
  }
  drag = null;
});

renderGrid();
</script></body></html>]==]

-- ---------- Panneau ----------
local function hide()
  if panel and panel:isVisible() then
    panel:hide()
    lastHide = hs.timer.secondsSinceEpoch()
  end
end

local function hideAndRefocus()
  hide()
  if previousWin then previousWin:focus() end
end

-- Après une modification : recalcule les profils et réaffiche le panneau à jour
local function refresh(toast)
  rebuild()
  bindProfileHotkeys()
  if toast then hs.alert.show(toast) end
  M:show(previousWin)
end

local function onMessage(msg)
  local body = msg.body
  if type(body) ~= "table" then return end
  if body.type == "close" then
    hideAndRefocus()
  elseif body.type == "apply" then
    hideAndRefocus()
    M:apply(body.name)
  elseif body.type == "save" and pending then
    local saved
    if type(body.from) == "string" then
      saved = editProfile(body.from, body.name, body.excluded)
    else
      for _, appName in ipairs(body.excluded or {}) do pending.rects[appName] = nil end
      saved = saveProfile(body.name, pending)
    end
    if saved then refresh("Profil « " .. saved .. " » enregistré") end
  elseif body.type == "delete" and custom[body.name] then
    custom[body.name] = nil
    writeCustom()
    refresh()
  elseif body.type == "order" and type(body.names) == "table" then
    hs.settings.set("windr.order", body.names)
    bindProfileHotkeys()
  elseif body.type == "size" and panel then
    local f = panel:frame()
    f.h = body.h
    panel:frame(f)
  end
end

local function ensurePanel()
  if panel then return panel end
  usercontent = hs.webview.usercontent.new("windr"):setCallback(onMessage)
  panel = hs.webview.new({ x = 0, y = 0, w = 10, h = 10 }, {}, usercontent)
    :windowStyle({ "borderless" })
    :level(hs.drawing.windowLevels.popUpMenu)
    :behaviorAsLabels({ "canJoinAllSpaces", "transient" })
    :transparent(true)
    :shadow(true)
    :allowTextEntry(true)
    :deleteOnClose(false)
    :windowCallback(function(action, _, state)
      if action == "focusChange" and not state then hide() end
    end)
  return panel
end

--- Windr:show()
--- Method
--- Ouvre le panneau sous l'icône de la barre de menus.
function M:show(prev)
  previousWin = prev or hs.window.focusedWindow()
  local data = buildData()
  local cards = #data.profiles + 1
  local rows = math.ceil(cards / data.cols)
  local previewH = math.floor((CARD_W - 12) * data.screen.h / data.screen.w)
  local width = PAD * 2 + data.contentW + 2
  local height = PAD * 2 + 48 + rows * (previewH + 52) + (rows - 1) * GAP + 32

  -- Sous l'icône, contenu dans l'écran
  local mf = menu:frame()
  local scr = (hs.screen.find(hs.geometry.point(mf.x, mf.y)) or hs.screen.mainScreen()):frame()
  local x = mf.x + mf.w / 2 - width / 2
  x = math.max(scr.x + 8, math.min(x, scr.x + scr.w - width - 8))
  local y = mf.y + mf.h + 6

  ensurePanel()
  panel:frame({ x = x, y = y, w = width, h = height })
  panel:html(HTML_HEAD .. hs.json.encode(data) .. HTML_TAIL)
  hs.focus()
  panel:show():bringToFront(true)
  timers.focus = hs.timer.doAfter(0.05, function()
    local w = panel:hswindow()
    if w then w:focus() end
  end)
end

--- Windr:toggle()
--- Method
--- Ouvre ou ferme le panneau.
function M:toggle()
  if panel and panel:isVisible() then
    hideAndRefocus()
  elseif hs.timer.secondsSinceEpoch() - lastHide > 0.3 then
    -- évite la réouverture quand le clic sur l'icône vient de fermer le panneau
    M:show()
  end
end

-- ---------- Icône barre de menus ----------
local function makeIcon()
  local c = hs.canvas.new({ x = 0, y = 0, w = 18, h = 18 })
  local function el(props)
    props.strokeColor, props.strokeWidth, props.action = { white = 0 }, 1.5, "stroke"
    return props
  end
  c[1] = el({ type = "rectangle", frame = { x = 2, y = 3, w = 14, h = 12 },
              roundedRectRadii = { xRadius = 2, yRadius = 2 } })
  c[2] = el({ type = "segments", coordinates = { { x = 9, y = 3 }, { x = 9, y = 15 } } })
  c[3] = el({ type = "segments", coordinates = { { x = 9, y = 9 }, { x = 16, y = 9 } } })
  local img = c:imageFromCanvas()
  c:delete()
  return img
end

--- Windr:start([options])
--- Method
--- Démarre Windr. Options (toutes facultatives) :
---  * hotkey : { mods, key } pour ouvrir le panneau (défaut ⌘⌥⌃Espace), false pour aucun
---  * profileHotkeys : modificateurs pour appliquer les profils 1-9 (ex. {"cmd","alt","ctrl"})
---  * layouts : profils de départ, même format que le fichier JSON
---  * profilesFile : chemin du fichier des profils capturés
---  * ignore : liste de bundle IDs à ne jamais capturer
function M:start(options)
  for k, v in pairs(options or {}) do config[k] = v end
  for _, id in ipairs(config.ignore or {}) do IGNORED[id] = true end
  for name in pairs(config.layouts) do builtin[name] = true end
  custom = loadCustom()
  rebuild()

  menu = hs.menubar.new()
  menu:setIcon(makeIcon(), true)
  menu:setTooltip("Windr")
  menu:setClickCallback(function() M:toggle() end)

  if config.hotkey then
    toggleHotkey = hs.hotkey.bind(config.hotkey[1], config.hotkey[2], function() M:toggle() end)
  end
  bindProfileHotkeys()
  return self
end

--- Windr:stop()
--- Method
--- Retire l'icône et les raccourcis.
function M:stop()
  hide()
  if menu then menu:delete(); menu = nil end
  if toggleHotkey then toggleHotkey:delete(); toggleHotkey = nil end
  for _, hk in ipairs(profileHotkeys) do hk:delete() end
  profileHotkeys = {}
  return self
end

return obj
