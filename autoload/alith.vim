vim9script

final propName = 'plugin-alith'
if prop_type_get(propName) == {}
  prop_type_add(propName, {highlight: 'IncSearch', priority: 100})
endif
var hlPopupIdList: list<number>

export def Alith(line1: number, line2: number, cmdline_regex: string = '')
  if cmdline_regex !=# ''
    DoAlign(line1, line2, cmdline_regex)
    return
  endif

  augroup plugin-alith
    autocmd!
    execute printf('autocmd CmdlineChanged @ Preview(%d, %d, getcmdline())|redraw', line1, line2)
    execute printf('autocmd TextChanged,TextChangedI,CursorMoved * Preview(%d, %d, getline("."))|redraw', line1, line2)
  augroup END

  var regex = ''
  try
    regex = input('regex> ')
  catch /^Vim:Interrupt$/
    # Fallthrough
  catch
    echohl Error
    echomsg v:throwpoint
    echomsg v:exception
    echohl NONE
  finally
    ClearPreviewHighlights()
    augroup plugin-alith
      autocmd!
    augroup END
  endtry
  if regex ==# ''
    echo 'Canceled.'
    return
  endif
  DoAlign(line1, line2, regex)
enddef

def DoAlign(line1: number, line2: number, reg: string)
  var poslist = GetMatchPosList(line1, line2, reg)
  if poslist->empty()
    return
  endif

  var sectionLens: dict<list<list<number>>>
  final LenInBytes = 0
  final LenInWidth = 1
  {
    var linestr: string
    var prevline = 0
    var prevcol = 1
    for p in poslist
      var line = p[0]
      var col = p[1]
      if line != prevline
        sectionLens[line] = []
        prevline = line
        prevcol = 1
        linestr = getline(line)
      endif

      sectionLens[line]->add([
        col - prevcol,
        linestr->strpart(prevcol - 1, col - prevcol)->strdisplaywidth()
      ])
      prevcol = col
    endfor
  }

  # maxLens: [Max length for section 1, Max length for secton 2, ...]
  var maxLens: list<number>
  for lens in values(sectionLens)
    var repeatTimes = len(lens)
    if repeatTimes > len(maxLens)
      for _ in range(repeatTimes - len(maxLens))
        maxLens->add(0)
      endfor
    endif
    for i in range(repeatTimes)
      var l = lens[i][LenInWidth]
      if l > maxLens[i]
        maxLens[i] = l
      endif
    endfor
  endfor

  # Format lines.
  for [linenr_str, lens] in items(sectionLens)
    var linenr = linenr_str->str2nr()
    var linerest = getline(linenr)
    var formatted = ''
    var i = 0
    for l in lens
      formatted ..= strpart(linerest, 0, l[LenInBytes])
      linerest = strpart(linerest, l[LenInBytes])
      if linerest !=# ''  # Avoid adding meaningless whitespaces at EOL.
        formatted ..= repeat(' ', maxLens[i] - l[LenInWidth])
      endif
      i += 1
    endfor
    formatted ..= linerest
    setline(linenr, formatted)
  endfor
enddef

# Highlight matched strings
def Preview(line1: number, line2: number, reg: string)
  var curbufnr = GetCurrentBufnr()
  var poslist =
    CallInBuffer(curbufnr, function('GetMatchPosList', [line1, line2, reg, true]))
    ->map((_, v) => {
      v[3] += 1
      return v
    })
  var hlEolPoslist: list<list<number>>
  var prevline = 0
  var colEOL = 0
  for pos in poslist
    if prevline != pos[0]
      prevline = pos[0]
      colEOL = CallInBuffer(curbufnr, function('GetEOLCol', [pos[0]]))
    endif
    if pos[1] >= colEOL
      hlEolPoslist->add([pos[0], pos[1]])
    endif
  endfor

  ClearPreviewHighlights()

  prop_add_list({bufnr: curbufnr, type: propName}, poslist)
  if !empty(hlEolPoslist)
    var curwinID = bufwinid(curbufnr)
    for pos in hlEolPoslist
      var p = screenpos(curwinID, pos[0], pos[1])
      var popupID =
        popup_create(' ', {line: p.row, col: p.col, highlight: 'IncSearch'})
      hlPopupIdList->add(popupID)
    endfor
  endif
enddef

def ClearPreviewHighlights()
  var curbufnr = GetCurrentBufnr()
  prop_remove({type: propName, bufnr: curbufnr, all: true})
  for id in hlPopupIdList
    popup_close(id)
  endfor
  hlPopupIdList = []
enddef


# Returns matched string positions in this form:
# [
#   [startline1, startcol1, endline1, endcol1],
#   [startline2, startcol2, endline2, endcol2],
#   ...
# ]
# The columns are in byte index.
def GetMatchPosList(line1: number, line2: number, reg: string, checkTimeout: bool = false): list<list<number>>
  if !IsValidRegex(reg)
    return []
  endif

  var firstcurpos = getcurpos()
  var poslist: list<list<number>>
  var lastline = line('$')
  var startTime = reltime()
  final notFound = [0, 0]
  try
    cursor(line1, 1)
    while true
      var startpos: list<number>
      var curpos = getcurpos()
      try
        startpos = searchpos(reg, 'cW', line2, &redrawtime)
      finally
        setpos('.', curpos)
      endtry
      if startpos == notFound
        break
      endif
      # NOTE: Even if startpos is found, endpos may not be found.
      #   :enew
      #   :call setline(1, '\')
      #   :normal! gg0
      #   :echo searchpos('\zs\ze\',  'cW') searchpos('\zs\ze\', 'ceW')
      #   "-> [1, 1] [0, 0]
      var endpos = searchpos(reg, 'ceW', line2, &redrawtime)
      if endpos == notFound
        # We don't know how long given regex matches actually, but we are sure
        # that given regex matches at startpos. Let's make endpos equals to
        # the startpos when the endpos is not found.
        endpos = startpos
      endif

      poslist->add(startpos + endpos)

      # Check timeouted
      if checkTimeout && reltime(startTime)->reltimefloat() * 1000 > &redrawtime
        break
      endif

      if (virtcol('.') + 1) < virtcol('$')
        normal! l
      else
        if endpos[0] == lastline  # At the end of file. Finish.
          break
        endif
        normal! j0
      endif
    endwhile
  finally
    setpos('.', firstcurpos)
  endtry
  return poslist
enddef

def IsValidRegex(reg: string): bool
  if reg ==# ''
    return false
  endif
  try
    eval '' =~# reg
  catch
    return false
  endtry
  return true
enddef

def GetEOLCol(line: number): number
  var curpos = getcurpos()
  var colEOL = 0
  try
    cursor(line, 1)
    colEOL = col('$')
  finally
    setpos('.', curpos)
  endtry
  return colEOL
enddef

def GetCurrentBufnr(): number
  if getcmdwintype() !=# ''
    return bufnr('#')
  endif
  return bufnr('%')
enddef

var FuncWrapper: func(): void
def CallInBuffer(bufnr: number, F: func): any
  var winID = bufwinid(bufnr)
  var retval: any
  FuncWrapper = () => {
    retval = F()
  }
  try
    call win_execute(winID, 'call FuncWrapper()')
  catch
    # TODO: Show error message?
    # Provide g:alith#verbose or g:alith#log_error like options?
  endtry
  return retval
enddef
