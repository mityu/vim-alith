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

  var sectionLens: dict<list<number>>
  {
    var prevline = 0
    var prevcol = 1
    for p in poslist
      if p[0] != prevline
        sectionLens[p[0]] = []
        prevline = p[0]
        prevcol = 1
      endif
      sectionLens[p[0]]->add(p[1] - prevcol)
      prevcol = p[1]
    endfor
  }

  var maxLens: list<number>
  for lens in values(sectionLens)
    var repeatTimes = len(lens)
    if repeatTimes > len(maxLens)
      for _ in range(repeatTimes - len(maxLens))
        maxLens->add(0)
      endfor
    endif
    for i in range(repeatTimes)
      var l = lens[i]
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
      formatted ..= strpart(linerest, 0, l) .. repeat(' ', maxLens[i] - l)
      linerest = linerest[l :]
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

  var curpos = getcurpos()
  var poslist: list<list<number>>
  var lastline = line('$')
  var startTime = reltime()
  try
    cursor(line1, 1)
    while search(reg, 'cW', line2, &redrawtime) != 0
      var startpos = getcurpos()[1 : 2]
      search(reg, 'ceW', line2, &redrawtime)
      var endpos = getcurpos()[1 : 2]

      poslist->add(startpos + endpos)

      # Check timeouted
      if reltime(startTime)->reltimefloat() * 1000 > &redrawtime
        break
      endif

      # `silent!` is to silence beep.
      # Checking col('$') may be smarter, but I'm not sure it surely work when
      # 'virtualedit' option is set.
      silent! normal! l
      if col('.') == endpos[1]
        if endpos[0] == lastline  # At the end of file. Finish.
          break
        endif
        normal! j0
      endif
    endwhile
  finally
    setpos('.', curpos)
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
