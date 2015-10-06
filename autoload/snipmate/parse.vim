" Snippet definition parsing code

function! s:sfile() abort
    return expand('<sfile>')
endfunction

let s:parser_proto = {}
let s:special_chars = "$`\n"

function! s:new_parser(text) abort
    let ret = copy(s:parser_proto)
    let ret.input = a:text
    let ret.len = strlen(ret.input)
    let ret.pos = -1
    let ret.indent = 0
    let ret.value = []
    let ret.vars = {}
    let ret.stored_lines = []
    call ret.advance()
    return ret
endfunction

function! s:parser_advance(...) dict abort
    let self.pos += a:0 ? a:1 : 1
    let self.next = self.input[self.pos]
endfunction

function! s:parser_same(tok) dict abort
    if self.next == a:tok
        call self.advance()
        return 1
    else
        return 0
    endif
endfunction

function! s:parser_id() dict abort
    if self.input[(self.pos):(self.pos+5)] == 'VISUAL'
        call self.advance(6)
        return 'VISUAL'
    elseif self.next =~ '\d'
        let end = matchend(self.input, '\d\+', self.pos)
        let res = strpart(self.input, self.pos, end - self.pos)
        call self.advance(end - self.pos)
        return +res " force conversion to Number
    endif
    return -1
endfunction

function! s:parser_add_var(var) dict abort
    let id = a:var[0]
    if !has_key(self.vars, id)
        let self.vars[id] = { 'instances' : [] }
    endif
    call add(self.vars[id].instances, a:var)
endfunction

function! s:parser_var() dict abort
    let ret = []
    if self.same('{')
        let id = self.id()
        if id >= 0
            call add(ret, id)
            call extend(ret, self.varend())
        endif
    else
        let id = self.id()
        if id >= 0
            call add(ret, id)
        endif
    endif
    return ret
endfunction

function! s:parser_varend() dict abort
    let ret = []
    if self.same(':')
        call extend(ret, self.placeholder())
    elseif self.same('/')
        call add(ret, self.subst())
    endif
    call self.same('}')
    return ret
endfunction

function! s:parser_placeholder() dict abort
    return self.text('}')
endfunction

function! s:parser_subst() dict abort
    let ret = {}
    let ret.pat = join(self.string('/'))
    if self.same('/')
        let ret.sub = join(self.string('/}'))
    endif
    if self.same('/')
        let ret.flags = join(self.string('}'))
    endif
    return ret
endfunction

function! s:parser_expr() dict abort
    let str = join(self.string('`'))
    call self.same('`')
    return snipmate#util#eval(str)
endfunction

function! s:parser_string(till) dict abort
    let res = []
    let val = ''
    let till = '\V\[' . escape(a:till, '\') . ']'

    while self.pos < self.len
        if self.same('\')
            if self.next != "\n"
                let val .= self.next
            endif
            call self.advance()
        elseif self.next =~# till
            break
        elseif self.next == "\t"
            let self.indent += 1
            let val .= s:indent(1)
            call self.advance()
        else
            let val .= self.next
            call self.advance()
        endif
    endwhile

    if !empty(val)
        call add(res, val)
    endif

    return res
endfunction

function! s:join_consecutive_strings(list) abort
    let list = a:list
    let pos = 0
    while pos + 1 < len(list)
        if type(list[pos]) == type('') && type(list[pos+1]) == type('')
            let list[pos] .= list[pos+1]
            call remove(list, pos + 1)
        else
            let pos += 1
        endif
    endwhile
endfunction

function! s:parser_text(till) dict abort
    let ret = []

    while self.pos < self.len && self.next !=# a:till
        let lines = []

        if self.same('$')
            let var = self.var()
            if !empty(var)
                if var[0] is# 'VISUAL'
                    let lines = s:visual_placeholder(var, self.indent)
                elseif var[0] >= 0
                    call add(ret, var)
                    call self.add_var(var)
                endif
            endif
        elseif self.same('`')
            let lines = split(self.expr(), "\n", 1)
        else
            let lines = self.string(a:till . s:special_chars)
        endif

        if !empty(lines)
            call add(ret, lines[0])
            call extend(self.stored_lines, lines[1:])
        endif
    endwhile

    call s:join_consecutive_strings(ret)
    return ret
endfunction

function! s:parser_line() dict abort
    let ret = []
    if !empty(self.stored_lines)
        call add(ret, remove(self.stored_lines, 0))
    else
        call extend(ret, self.text("\n"))
        call self.same("\n")
    endif
    let self.indent = 0
    return ret
endfunction

function! s:parser_parse() dict abort
    while self.pos < self.len || !empty(self.stored_lines)
        let line = self.line()
        call add(self.value, line)
    endwhile
endfunction

call extend(s:parser_proto, snipmate#util#add_methods(s:sfile(), 'parser',
            \ [ 'advance', 'same', 'id', 'add_var', 'var', 'varend',
            \   'line', 'string',
            \   'placeholder', 'subst', 'expr', 'text', 'parse',
            \ ]), 'error')

function! s:indent(count) abort
    if &expandtab
        let shift = repeat(' ', snipmate#util#tabwidth())
    else
        let shift = "\t"
    endif
    return repeat(shift, a:count)
endfunction

function! s:visual_placeholder(var, indent) abort
    let arg = get(a:var, 1, {})
    if type(arg) == type({})
        let pat = get(arg, 'pat', '')
        let sub = get(arg, 'sub', '')
        let flags = get(arg, 'flags', '')
        let content = split(substitute(get(b:, 'snipmate_visual', ''), pat, sub, flags), "\n", 1)
    else
        let content = split(get(b:, 'snipmate_visual', arg), "\n", 1)
    endif

    let indent = s:indent(a:indent)
    call map(content, '(v:key != 0) ? indent . v:val : v:val')

    return content
endfunction

function! snipmate#parse#snippet(text) abort
    let parser = s:new_parser(a:text)
    call parser.parse()
    unlet! b:snipmate_visual
    return [parser.value, parser.vars]
endfunction
