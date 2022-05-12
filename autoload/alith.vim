vim9script

final propName = 'plugin-alith'
if prop_type_get(propName) == {}
  prop_type_add(propName, {highlight: 'IncSearch', priority: 100})
endif

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
  finally
    prop_remove({type: propName, bufnr: GetCurrentBufnr(), all: true})
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
  # TODO: Add support for highlight of the end of line.
  var curbufnr = GetCurrentBufnr()
  var poslist =
    CallInBuffer(curbufnr, function('GetMatchPosList', [line1, line2, reg]))
    ->map((_, v) => {
    v[3] += 1
    return v
  })
  prop_remove({type: propName, bufnr: curbufnr, all: true})
  prop_add_list({bufnr: curbufnr, type: propName}, poslist)
enddef


# Returns matched string positions in this form:
# [
#   [startline1, startcol1, endline1, endcol1],
#   [startline2, startcol2, endline2, endcol2],
#   ...
# ]
def GetMatchPosList(line1: number, line2: number, reg: string): list<list<number>>
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
      var endpos = searchpos(reg, 'ceW', line2, &redrawtime)

      poslist->add(startpos + endpos)

      # Check timeouted
      if reltime(startTime)->reltimefloat() * 1000 > &redrawtime
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
  try
    eval '' =~# reg
  catch
    return false
  endtry
  return true
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
