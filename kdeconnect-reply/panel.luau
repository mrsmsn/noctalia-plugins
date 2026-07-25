--!nonstrict
-- Reply to KDE Connect notifications from a native Noctalia panel.
--
-- Noctalia's own notification UI cannot deliver an inline reply to kdeconnectd
-- (the notification is already closed by the time the action is invoked), so
-- this panel talks to the daemon's per-notification DBus objects directly:
-- enumerate them, keep the ones with a non-empty replyId, and send the typed
-- text with sendReply().

local SERVICE = "org.kde.kdeconnect.daemon"
local IFACE = "org.kde.kdeconnect.device.notifications.notification"

-- One JSON array of replyable notifications. GetAll output is busctl's typed
-- JSON envelope, so jq unwraps each property's .data.
local LIST_CMD = [[
busctl --user tree --list org.kde.kdeconnect.daemon 2>/dev/null \
  | grep -E '/notifications/[0-9]+$' \
  | while read -r p; do
      busctl --user --json=short call org.kde.kdeconnect.daemon "$p" \
        org.freedesktop.DBus.Properties GetAll s \
        org.kde.kdeconnect.device.notifications.notification \
        | jq -c --arg path "$p" '.data[0] | {
            path: $path,
            appName: .appName.data,
            title: .title.data,
            text: .text.data,
            iconPath: .iconPath.data,
            replyId: .replyId.data,
            dismissable: .dismissable.data
          }'
    done | jq -sc '[.[] | select(.replyId != null and .replyId != "")]'
]]

local conversations = {}
local selectedIndex = 1
local loading = false
local sending = false
local dismissing = false
local status = nil

local render

-- Per-row callbacks need distinct global names; the reconciler dispatches
-- callbacks by name only (same pattern as the official notes plugin).
local env = getfenv()
local function rowCallback(prefix, index, fn)
  local name = prefix .. "_" .. index
  env[name] = fn
  return name
end

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

local function shellQuote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function truncate(s, maxChars)
  local len = utf8.len(s)
  if len == nil or len <= maxChars then
    return s
  end
  return s:sub(1, utf8.offset(s, maxChars + 1) - 1) .. "…"
end

-- Notification bodies may carry markup (<br/> etc.); flatten to one plain line.
local function plainText(text)
  return (tostring(text or ""):gsub("<[^>]->", " "):gsub("%s+", " "))
end

local function snippet(text, maxChars)
  return truncate(plainText(text), maxChars)
end

local function refresh()
  loading = true
  status = nil
  render()
  noctalia.runAsync(LIST_CMD, function(result)
    loading = false
    local list = {}
    if result.exitCode == 0 then
      local decoded = noctalia.json.decode(result.stdout)
      if type(decoded) == "table" then
        list = decoded
      end
    end
    -- Newest first: notification object paths end in an increasing counter.
    for _, conv in ipairs(list) do
      conv.num = tonumber(tostring(conv.path):match("/(%d+)$")) or 0
    end
    table.sort(list, function(a, b)
      return a.num > b.num
    end)
    conversations = list
    if selectedIndex < 1 or selectedIndex > #conversations then
      selectedIndex = 1
    end
    render()
  end, 10000)
end

local function send(text)
  local conv = conversations[selectedIndex]
  if sending or conv == nil or text == "" then
    return
  end
  sending = true
  status = tr("sending")
  render()
  local cmd = `busctl --user call {SERVICE} {shellQuote(conv.path)} {IFACE} sendReply s {shellQuote(text)}`
  noctalia.runAsync(cmd, function(result)
    sending = false
    if result.exitCode == 0 then
      noctalia.notify(tr("title"), tr("sent", { title = conv.title }))
      panel.close()
    else
      status = tr("send_failed") .. ": " .. (result.stderr ~= "" and result.stderr or `exit {result.exitCode}`)
      render()
    end
  end, 10000)
end

-- dismiss() removes the daemon-side object only after the phone confirms, so an
-- immediate refresh() would race and re-list the notification; drop it locally.
local function dismiss(index)
  local conv = conversations[index]
  if sending or dismissing or conv == nil then
    return
  end
  dismissing = true
  local cmd = `busctl --user call {SERVICE} {shellQuote(conv.path)} {IFACE} dismiss`
  noctalia.runAsync(cmd, function(result)
    dismissing = false
    if result.exitCode == 0 then
      table.remove(conversations, index)
      if selectedIndex < 1 or selectedIndex > #conversations then
        selectedIndex = 1
      end
    else
      status = tr("dismiss_failed") .. ": " .. (result.stderr ~= "" and result.stderr or `exit {result.exitCode}`)
    end
    render()
  end, 10000)
end

local function convRow(conv, index)
  local isSelected = index == selectedIndex
  local children = {}
  if conv.iconPath ~= nil and conv.iconPath ~= "" then
    table.insert(children, ui.image({ path = conv.iconPath, width = 28, height = 28, radius = 14, fit = "cover" }))
  else
    table.insert(children, ui.glyph({ name = "message-circle", size = 20, color = "on_surface_variant" }))
  end
  local title = conv.title ~= "" and conv.title or conv.appName
  table.insert(children, ui.button({
    text = truncate(tostring(title), 20) .. "  ·  " .. snippet(conv.text, 34),
    variant = isSelected and "primary" or "ghost",
    contentAlign = "start",
    flexGrow = 1,
    onClick = rowCallback("onPick", index, function()
      selectedIndex = index
      render()
    end),
  }))
  if conv.dismissable == true then
    table.insert(children, ui.button({
      glyph = "trash",
      variant = "ghost",
      onClick = rowCallback("onDismiss", index, function()
        dismiss(index)
      end),
    }))
  end
  -- Selection is part of the key: retained buttons keep their variant, so the
  -- row is recreated when selection flips.
  return ui.row({ key = conv.path .. (isSelected and "-sel" or ""), gap = 8, align = "center" }, children)
end

local function body()
  if #conversations == 0 then
    return ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 8 }, {
      ui.glyph({ name = "message-off", size = 32, color = "on_surface_variant" }),
      ui.label({ text = loading and tr("loading") or tr("empty"), color = "on_surface_variant" }),
    })
  end

  local rows = {}
  for index, conv in ipairs(conversations) do
    table.insert(rows, convRow(conv, index))
  end

  local children = {
    ui.scroll({ flexGrow = 1, gap = 4, align = "stretch" }, rows),
    ui.separator({}),
  }
  local conv = conversations[selectedIndex]
  if conv ~= nil then
    table.insert(children, ui.column({ gap = 4, align = "stretch" }, {
      ui.label({ text = tostring(conv.title), fontWeight = "bold", color = "on_surface" }),
      ui.label({ text = plainText(conv.text), color = "on_surface_variant", maxLines = 3 }),
    }))
  end
  table.insert(children, ui.input({
    key = "reply",
    placeholder = tr("placeholder"),
    onSubmit = "onReplySubmit",
  }))
  if status ~= nil then
    table.insert(children, ui.label({ text = status, color = sending and "on_surface_variant" or "error" }))
  end
  return ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, children)
end

render = function()
  panel.render(ui.column({ flexGrow = 1, gap = 16, align = "stretch" }, {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.glyph({ name = "message-circle", size = 18, color = "primary" }),
      ui.label({ text = tr("title"), fontSize = 16, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      ui.button({ glyph = "refresh", variant = "ghost", onClick = "onRefresh" }),
      ui.button({ glyph = "close", variant = "ghost", onClick = "onCloseClicked" }),
    }),
    body(),
  }))
end

function onReplySubmit(value)
  send(noctalia.string.trim(value or ""))
end

function onRefresh()
  refresh()
end

function onCloseClicked()
  panel.close()
end

function onOpen(_context)
  selectedIndex = 1
  refresh()
end
