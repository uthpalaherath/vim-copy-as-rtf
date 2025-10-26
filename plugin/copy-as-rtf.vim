" Vim plugin for copying syntax highlighted code as RTF on Windows/macOS/X11
" Orig Author: Nathan Witmer <nwitmer@gmail.com>
" Last Change: 2020-09-09
" By:          Wu Yongwei <wuyongwei@gmail.com>
" License:     WTFPL

if exists('g:loaded_copy_as_rtf')
  finish
endif
let g:loaded_copy_as_rtf = 1

" Set this to 1 to tell copy_as_rtf to use the local buffer instead of a scratch
" buffer with the selected code. Use this if the syntax highlighting isn't
" correctly handling your code when removed from its context in its original
" file.
if !exists('g:copy_as_rtf_using_local_buffer')
  let g:copy_as_rtf_using_local_buffer = 0
endif

" Set this to 1 to preserve the indentation as-is when converting to RTF.
" Otherwise, the selected lines are outdented as far as possible before
" conversion.
if !exists('g:copy_as_rtf_preserve_indent')
  let g:copy_as_rtf_preserve_indent = 0
endif

if has('win32') && has('clipboard')
  function s:Copy_as_RTF()
    %yank *
    silent exec '!start /min powershell -noprofile "gcb | scb -as"'
  endfunction
elseif has('x11') && executable('xclip')
  function s:Copy_as_RTF()
    silent exe '%!xclip -selection clipboard -t "text/html" -i'
  endfunction
elseif executable('pbcopy') && executable('textutil')
  function s:Copy_as_RTF()
    silent exe '%!textutil -convert rtf -stdin -stdout | pbcopy'
  endfunction
else
  if !exists('g:copy_as_rtf_silence_on_errors') || g:copy_as_rtf_silence_on_errors == 0
    echomsg 'Cannot load copy-as-rtf plugin: unsupported platform'
  endif
  finish
endif

" Force HTML body/background to white in the HTML buffer produced by TOhtml
function! s:ForceWhiteBackgroundHTML()
  if !exists('g:copy_as_rtf_force_white_bg') || !g:copy_as_rtf_force_white_bg
    return
  endif

  " Assume current buffer is the HTML buffer created by tohtml#Convert2HTML().
  " We'll perform a few defensive substitutions to make the body/background white.
  " Use 'silent' to avoid messages interfering with plugin flow.

  " 1) Replace body bgcolor="..." with bgcolor="white"
  silent %s/\(<body[^>]*\)\v(bgcolor\s*=\s*")[^"]*(")/\1\2white\3/ge

  " 2) Remove any body inline style that sets background or add white if missing:
  "   remove background declarations inside style attributes
  silent %s/\v(background(-color)?\s*:\s*[^;"]+;?)/background-color: white;/ge

  " 3) If <style> block or external CSS has body { background: ... } replace it
  silent %s/\v(body\s*\{[^}]*\})/\=substitute(submatch(0), '\vbackground[^;:}]+;?', 'background-color: white;', 'g')/ge

  " 4) Ensure there's an explicit inline body style with white background if none exists
  " If <body ...> has no style attr add one with white background
  if match(getline(1, '$')->join("\n"), '<body[^>]*style=') == -1
    " Add style attribute after <body...> start tag
    " We do a substitution on first occurrence of <body ...>
    silent 1,%s/\(<body\([^>]*\)\)>/\=submatch(0) =~ 'style=' ? submatch(0) : substitute(submatch(0), '>$', ' style="background-color: white;">', '')/e
  endif

  " 5) As a last resort, append a <style> block near the top that forces white body background
  if match(getline(1, 40)->join("\n"), 'body\s*\{[^}]*background-color') == -1
    " insert a small style block after the <head> tag if present, otherwise at top
    let l:headline = search('<head\>', 'nw')
    if l:headline > 0
      call append(l:headline, ['<style type="text/css">', '  body { background-color: white !important; }', '</style>'])
    else
      call append(0, ['<style type="text/css">', '  body { background-color: white !important; }', '</style>'])
    endif
  endif

  " Ensure buffer changed (so TOhtml's buffer content is what we modified)
  silent noautocmd write
endfunction

" copy the current buffer or selected text as RTF
"
" bufnr - the buffer number of the current buffer
" line1 - the start line of the selection
" line2 - the ending line of the selection
function! s:CopyRTF(bufnr, line1, line2)

  " check at runtime since this plugin may not load before this one
  if !exists(':TOhtml')
    echoerr 'cannot load copy-as-rtf plugin, TOhtml command not found.'
    finish
  endif

  " save the alternate file and restore it at the end
  let l:alternate=bufnr(@#)

  if g:copy_as_rtf_using_local_buffer
    let lines = getline(a:line1, a:line2)

    if !g:copy_as_rtf_preserve_indent
      call s:RemoveCommonIndentation(a:line1, a:line2)
    endif
    call tohtml#Convert2HTML(a:line1, a:line2)
    call s:ForceWhiteBackgroundHTML()
    call Copy_as_RTF()

    silent bd!
    silent call setline(a:line1, lines)
  else

    " open a new scratch buffer
    let orig_ft = &ft
    let l:orig_bg = &background
    let l:orig_bg = &background
    if exists('g:copy_as_rtf_force_light_bg') && g:copy_as_rtf_force_light_bg
      set background=light
    endif
    let l:orig_nu = &number
    let l:orig_nuw = &numberwidth
    if exists("b:is_bash")
      let l:is_bash = b:is_bash
    endif
    new __copy_as_rtf__
    " enable the same syntax highlighting
    if exists("l:is_bash")
      let b:is_bash=l:is_bash
    endif
    let &ft=orig_ft
    let &background=l:orig_bg
    let &number=l:orig_nu
    let &numberwidth=l:orig_nuw
    set buftype=nofile
    set bufhidden=hide
    setlocal noswapfile

    " copy the selection into the scratch buffer
    call setline(1, getbufline(a:bufnr, a:line1, a:line2))

    if !g:copy_as_rtf_preserve_indent
      call s:RemoveCommonIndentation(1, line('$'))
    endif

    call tohtml#Convert2HTML(1, line('$'))
    call s:ForceWhiteBackgroundHTML()
    call s:Copy_as_RTF()
    silent bd!
    silent bd!
  endif

  let @# = l:alternate
  echomsg "RTF copied to clipboard"
endfunction

" outdent selection to the least indented level
function! s:RemoveCommonIndentation(line1, line2)
  " normalize indentation
  silent exe a:line1 . ',' . a:line2 . 'retab'

  let lines_with_code = filter(range(a:line1, a:line2), 'match(getline(v:val), ''\S'') >= 0')
  let minimum_indent = min(map(lines_with_code, 'indent(v:val)'))
  let pattern = '^\s\{' . minimum_indent . '}'
  call setline(a:line1, map(getline(a:line1, a:line2), 'substitute(v:val, pattern, "", "")'))
endfunction

command! -range=% CopyRTF :call s:CopyRTF(bufnr('%'),<line1>,<line2>)
