let s:suite = themis#suite('alith.vim')
let s:assert = themis#helper('assert')

" List not only legacy functions but also :def functions.
function! s:getScriptFuncs(path) abort
  let SNR = vital#themis#import('Vim.ScriptLocal').sid(a:path)
  let fs = execute(printf("function /^\<SNR>%d_", SNR))
  let pattern = '^\v<%(def|function)>\s+\zs\<SNR\>\d+_(\w{-})\ze\('
  let funcs = {}
  for f in split(fs, "\n")
    let [fullname, name] = matchlist(f, pattern)[0 : 1]
    let funcs[name] = function(fullname)
  endfor
  return funcs
endfunction

let s:funcs = s:getScriptFuncs('autoload/alith.vim')
call themis#func_alias(s:funcs)


function s:suite.before_each()
  %delete _
endfunction

function s:suite.__GetMatchPosList__()
  let child = themis#suite('GetMatchPosList()')

  function child.test_no_match()
    call s:assert.equals(s:funcs.GetMatchPosList(1, 1, '.'), [])
  endfunction

  function child.test_match_string()
    let lines =<< trim END
      aaa bbb
    END
    call setline(1, lines)
    call s:assert.equals(
          \s:funcs.GetMatchPosList(1, len(lines), 'aaa'),
          \[[1, 1, 1, 3]])
  endfunction

  function child.test_with_empty_line()
    let lines =<< trim END
      |aaa|bbb|
      |c|d|

      |ee|ff|gg|
    END
    call setline(1, lines)
    let poslist = [[1, 5, 9], [1, 3, 5], [], [1, 4, 7, 10]]
    let ConvPos = {p, l1 ->
          \map(deepcopy(p), {i, v -> map(v, {_, w -> [i + l1, w, i + l1, w]})})
          \->flatten(1)
          \}
    let Check = {l1, l2 ->
          \ s:assert.equals(
          \     s:funcs.GetMatchPosList(l1, l2, '|'),
          \     ConvPos(poslist[l1 - 1 : l2 - 1], l1)
          \)}
    call Check(1, len(lines))
    call Check(1, 3)
    call Check(2, 4)
    call Check(2, 3)
  endfunction

  function child.test_regex_over_lines()
    let lines =<< trim END
      line1
      line2
      line3
    END
    call setline(1, lines)
    call s:assert.equals(s:funcs.GetMatchPosList(1, 3, 'line1\nline2'),
          \ [[1, 1, 2, 5]])
    call s:assert.equals(s:funcs.GetMatchPosList(1, 3, '2\nline3'),
          \ [[2, 5, 3, 5]])
    call s:assert.equals(s:funcs.GetMatchPosList(1, 3, 'line2\nline2'),
          \ [])
  endfunction

  function child.test_cursor_stays()
    call setline(1, ['|aa|bb|', '|a|b|'])
    call cursor(1, 1)
    call s:funcs.GetMatchPosList(1, 2, '|')
    call s:assert.equals(getcurpos()[1 : 2], [1, 1])
  endfunction

  function child.test_invalid_regex()
    call setline(1, 'a')
    call s:assert.equals(s:funcs.GetMatchPosList(1, 1, '\(a'), [])
  endfunction

  function child.test_zero_width_regex1()
    call setline(1, ['a', 'a'])
    call s:assert.equals(
          \s:funcs.GetMatchPosList(1, 2, 'a\zs'),
          \[[1, 2, 1, 2], [2, 2, 2, 2]])
  endfunction

  function child.test_zero_width_regex2()
    call setline(1, ['a, b', 'aa, b'])
    call s:assert.equals(
          \s:funcs.GetMatchPosList(1, 2, ',\zs'),
          \[[1, 3, 1, 3], [2, 4, 2, 4]])
  endfunction
endfunction

function s:suite.__Preview__()
  let child = themis#suite('Preview()')

  function child.after_each()
    %bwipeout!
  endfunction

  function child.test_show_matches_with_props()
    let lines =<< trim END
      aaa
      bbb
      aaa aaa
    END
    call setline(1, lines)
    call s:funcs.Preview(1, 3, 'aaa')
    call s:assert.equals(
          \prop_list(1)->map({_, v -> filter(v, 'v:key =~# "\\v<%(lnum|col|length)>"')}),
          \[#{col: 1, length: 3}])

    call s:assert.equals(
          \prop_list(3)->map({_, v -> filter(v, 'v:key =~# "\\v<%(lnum|col|length)>"')}),
          \[#{col: 1, length: 3}, #{col: 5, length: 3}])
  endfunction

  function child.test_clear_props_on_redraw()
    let lines =<< trim END
      aaa
    END
    call setline(1, lines)
    call s:funcs.Preview(1, 1, 'aaa')
    call s:assert.equals(
          \prop_list(1)->map({_, v -> filter(v, 'v:key =~# "\\v<%(lnum|col|length)>"')}),
          \[#{col: 1, length: 3}])
    call s:funcs.Preview(1, 1, 'does not exist')
    call s:assert.equals(prop_list(1), [])
  endfunction

  function child.test_match_over_multiple_lines()
    let lines =<< trim END
      line1
      line2
    END
    call setline(1, lines)
    call s:funcs.Preview(1, 2, 'ine1\nlin')
    call s:assert.equals(
          \prop_list(1)->map({_, v -> filter(v, 'v:key =~# "\\v<%(lnum|col|length)>"')}),
          \[#{col: 2, length: 5}])
    call s:assert.equals(
          \prop_list(2)->map({_, v -> filter(v, 'v:key =~# "\\v<%(lnum|col|length)>"')}),
          \[#{col: 1, length: 3}])
  endfunction
endfunction

function s:suite.__DoAlign__()
  let child = themis#suite('DoAlign()')

  function child.test_oneline()
    call setline(1, 'a, b, c')
    call s:funcs.DoAlign(1, 1, ',')
    call s:assert.equals(getline(1, '$'), ['a, b, c'])
  endfunction

  function child.test_multiline()
    call setline(1, ['a, b, c', 'aa, b, c'])
    call s:funcs.DoAlign(1, 2, ',')
    call s:assert.equals(getline(1, '$'), ['a , b, c', 'aa, b, c'])
  endfunction

  function child.test_before_colon()
    call setline(1, ['a: b', 'foo: bar'])
    call s:funcs.DoAlign(1, 2, ':')
    call s:assert.equals(getline(1, '$'), ['a  : b', 'foo: bar'])
  endfunction

  function child.test_after_colon()
    call setline(1, ['a: b', 'foo: bar'])
    call s:funcs.DoAlign(1, 2, ':\s*\zs\a')
    call s:assert.equals(getline(1, '$'), ['a:   b', 'foo: bar'])
  endfunction

  function child.test_different_number_of_matches()
    let lines =<< trim END
      |a|b|c|
      |aa|bb|
    END
    let expected =<< trim END
      |a |b |c|
      |aa|bb|
    END
    call setline(1, lines)
    call s:funcs.DoAlign(1, 2, '|')
    call s:assert.equals(getline(1, '$'), expected)
  endfunction

  function child.test_ignore_zero_matches_lines()
    let lines =<< trim END
      |a|b|c|
      no-separator
      |aa|bb|
    END
    let expected =<< trim END
      |a |b |c|
      no-separator
      |aa|bb|
    END
    call setline(1, lines)
    call s:funcs.DoAlign(1, 3, '|')
    call s:assert.equals(getline(1, '$'), expected)
  endfunction

  function child.test_zero_width_regex()
    call setline(1, ['a: b', 'aa: b'])
    call s:funcs.DoAlign(1, 3, ':\zs')
    call s:assert.equals(getline(1, '$'), ['a:  b', 'aa: b'])
  endfunction

  function child.test_cursor_stays()
    call setline(1, ['|aa|bb|', '|a|b|'])
    call cursor(1, 1)
    call s:funcs.DoAlign(1, 2, '|')
    call s:assert.equals(getcurpos()[1 : 2], [1, 1])
  endfunction
endfunction
