#!/usr/bin/env lsc
require! <[ x11 split ]>
{ words, keys } = require \prelude-ls

e, display <- x11.create-client!

X     = display.client
root  = display.screen[0].root

managed-ids = []
on-top-ids  = []

focus = root

action = do

  update-on-top = -> on-top-ids.for-each X.Raise-window

  min-width  = 50
  min-height = 50

  move : (id, x, y) ->
    return if id is root
    e, geom <- X.Get-geometry id
    return Error "Could not get geometry of #id: #e" if e
    new-x = geom.x-pos + x
    new-y = geom.y-pos + y
    X.Move-window id, new-x, new-y
  resize : (id, x, y) ->
    return if id is root
    e, geom <- X.Get-geometry id
    return Error "Could not get geometry of #id: #e" if e
    new-width  = Math.max (geom.width + x), min-width
    new-height = Math.max (geom.height + y), min-height
    X.Resize-window id, new-width, new-height
  focus : (id) ->
    X.Set-input-focus id
    focus := id
  raise : (id) ->
    return if id is root
    X.Raise-window id
    update-on-top!
  destroy: (id) ->
    return if id is root
    console.log "<-: #id"
    delete managed-ids[id]
  map : (id) -> X.Map-window id

manage = (id) ->

  return Error "Null window ID" unless id? # Sanity
  console.log "->: #id"

  e, attr <- X.Get-window-attributes id
  if e
    console.error "Error getting window attributes (wid #id): #e"
    return
  return if attr.override-redirect # Ignore pop-ups

  get-wm-class = (id, cb) ->
    e, prop <- X.Get-property 0 id, X.atoms.WM_CLASS, X.atoms.STRING, 0, 10000000
    return cb e if e
    switch prop.type
    | X.atoms.STRING =>
      # Data format:
      #
      #     progname<null>classname<null>
      #
      # where `<null>` is a null-character.
      null-char = String.from-char-code 0
      strings = prop.data.to-string!split null-char
      return cb null program : strings.0, class : strings.1
    | 0 => return cb null [ "" "" ] # No WM_CLASS set
    | _ => return cb "Unexpected non-string WM_CLASS"

  # Put Hudkit on top
  e, attr <- get-wm-class id
  if e
    console.error "Error getting window class (wid #id): #e"
    return
  switch attr.class
  | \Hudkit   => on-top-ids.push id
  | otherwise =>
    # Subscribe to window entry events
    do
      event-mask = x11.event-mask.EnterWindow
      X.Change-window-attributes id, { event-mask }

    # Remember window
    managed-ids[id] = true



# ----------
# BEGIN MAIN
# ----------



action.focus root

drag =
  target : null
  start  : x : 0 y : 0

event-mask = x11.event-mask.StructureNotify
  .|. x11.event-mask.SubstructureNotify
  .|. x11.event-mask.SubstructureRedirect
X
  # Subscribe to events
  ..Change-window-attributes root, { event-mask }, (err) ->
    # This callback isn't called on success; only on error.
    # I think it's a bug, but let's roll with it for now.
    if err.error is 10
      console.error 'Error: another window manager already running.'
      process.exit 1

  # Pick up existing windows
  ..QueryTree root, (e, tree) -> tree.children.for-each manage

  ..on 'error' console.error

  # Handle incoming events
  ..on 'event' (ev) ->
    { type, wid } = ev
    t =
      enter-notify : 7
      expose : 12
      create-notify : 16
      destroy-notify : 17
      unmap-notify : 18
      map-notify : 19
      map-request : 20
      configure-request : 23
    switch type
    | t.map-request       =>
      manage wid
      action.map wid
      action.raise wid
      action.focus wid
    | t.configure-request =>
      #action.resize wid, ev.width, ev.height
    | t.destroy-notify    =>
      action.destroy wid
      action.focus root
    | t.enter-notify      => action.focus wid

process.stdin .pipe split \\n
  .on \data (line) ->
    args = line |> words
    return unless args.length
    switch args.shift!
    | \resize =>
      return if focus is root
      console.log "Resizing #focus"
      x = args.shift! |> Number
      y = args.shift! |> Number
      if drag.target is null
        drag
          ..target  = focus
          ..start.x = x
          ..start.y = y
      delta-x   = x - drag.start.x
      delta-y   = y - drag.start.y
      drag.start
        ..x = x
        ..y = y
      action.resize drag.target, delta-x, delta-y
    | \move =>
      return if focus is root
      console.log "Moving #focus"
      x = args.shift! |> Number
      y = args.shift! |> Number
      if drag.target is null
        drag
          ..target = focus
          ..start.x = x
          ..start.y = y
      delta-x   = x - drag.start.x
      delta-y   = y - drag.start.y
      console.log "Moving #{drag.target} by #delta-x,#delta-y"
      drag.start
        ..x = x
        ..y = y
      action.move drag.target, delta-x, delta-y
    | \move-all =>
      return unless managed-ids.length
      x = args.shift! |> Number
      y = args.shift! |> Number
      if drag.start.x is null
        drag.start
          ..x = x
          ..y = y
      delta-x   = (x - drag.start.x) * 3
      delta-y   = (y - drag.start.y) * 3
      console.log "Moving all by #delta-x,#delta-y"
      drag.start
        ..x = x
        ..y = y
      keys managed-ids .for-each -> action.move it, delta-x, delta-y
    | \reset =>
      console.log "RESET"
      drag
        ..target = null
        ..start
          ..x = null
          ..y = null
    | \raise =>
      console.log "Raising #focus"
      action.raise focus
