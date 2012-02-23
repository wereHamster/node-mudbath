# Parser which converts output with ANSI color sequences into tokens or html.

parseSequence = (input) ->
    length = input.length
    return { cmd: input[length - 1], args: input.substring 2, length - 1 }

tokenize = (input, result = []) ->
    return [''] if input == ''

    input.replace /(\u001B\[.*?([@-~]))|([^\u001B]+)/g, (m) ->
        result.push m[0] == '\u001B' and parseSequence(m) or m

    return result

COLORS =
    0:  '',          1:  'bold',        4:  'underscore', 5:  'blink',
    30: 'fg-black',  31: 'fg-red',      32: 'fg-green',   33: 'fg-yellow',
    34: 'fg-blue',   35: 'fg-magenta',  36: 'fg-cyan',    37: 'fg-white'
    40: 'bg-black',  41: 'bg-red',      42: 'bg-green',   43: 'bg-yellow',
    44: 'bg-blue',   45: 'bg-magenta',  46: 'bg-cyan',    47: 'bg-white'

# Given a string with color escape sequences, return a <code> block with
# appropriately colored <span> elements.
exports.html = (str) ->
    result = tokenize(str).map (v) ->
        if typeof v == 'string'
            return v
        else if v.cmd == 'm'
            cls = v.args.split(';').map((v) -> COLORS[parseInt v]).join(' ')
            return "</span><span class=\"#{cls}\">"
        else
            return ''

    return "<code><pre><span>#{result.join('')}</span></pre></code>"
