trim = (str) -> str.replace(/^\s*|\s*$/g, '')

TemplateCache = {}
Partials = {}

tagOpen = '{{'
tagClose = '}}'

# Parses the given template between the start and end indexes.
Parse = (template, start = 0, end = template.length) ->
  # If we've got a cached parse tree for this template, return it.
  subtemplate = template[start..end]
  return TemplateCache[subtemplate] if template of TemplateCache

  # Set up fresh, clean parse and whitespace buffers.
  buffer = []
  whitespace = ''

  # Build a RegExp to match the start of a new tag.
  open  = ///((?:(\n)([#{' '}\t]*))?#{tagOpen})///g
  close = ///(#{tagClose})///g
  open.lastIndex = start

  # Start walking through the template, searching for opening tags between
  # start and end.
  while open.test(template)
    break if open.lastIndex >= end

    # Append any text content before the tag, save any intervening whitespace,
    # and advance into the tag itself.  We'll also save off information about
    # whether this tag is potentially "standalone", which would change the
    # processing semantics.
    firstContentOnLine = yes
    if open.lastIndex > 0
      buffer.push(RegExp.leftContext[start..])
      buffer.push(RegExp.$2) if RegExp.$2
      firstContentOnLine = RegExp.$2 == "\n"
    whitespace = RegExp.$3
    start = open.lastIndex

    # Build the pattern for finding the end of the tag.  Set Delimiter tags and
    # Triple Mustache tags also have mirrored characters, which need to be
    # accounted for and removed.
    offset   = 0
    offset   = 1 if template[start] in ['=', '{']
    endOfTag = switch template[start]
      when '=' then ///([=]#{tagClose})///g
      when '{' then ///([}]#{tagClose})///g
      else close
    endOfTag.lastIndex = start

    # Grab the tag contents, and advance the pointer beyond the end of the tag.
    throw "No end for tag!" unless endOfTag.test(template)
    tag   = RegExp.leftContext[start...]
    start = endOfTag.lastIndex

    # If the next character in the template is a newline, that implies that
    # this tag was the only content on this line.  Excepting the interpolating
    # tags, this means that the tag in question should disappear from the
    # rendered output completely.  If the tag was not "standalone", or it was
    # an interpolation tag, the whitespace we earlier removed should be re-
    # added.
    if (firstContentOnLine && template[start] == "\n" && /[\W{&]/.test(tag[0]))
      start++
    else
      buffer.push(whitespace)

    switch tag[0]
      # Comment Tag
      when '!' then null

      # Partial Tag
      when '>'
        buffer.push [ 'partial', whitespace, Parse(Partials[trim(tag[1..])])]

      # Set Delimiters Tag
      when '='
        [tagOpen, tagClose] = trim(tag[1..]).split(/\s+/)
        open  = ///(((\n)[#{' '}\t]*)?#{tagOpen})///g
        close = ///(#{tagClose})///g

      # Unescaped Interpolation Tag
      when '&', '{'
        buffer.push [ 'unescaped', trim(tag[1..]) ]

      # Escaped Interpolation Tag
      else
        buffer.push [ 'escaped', trim(tag) ]

    # Advance the lastIndex for the open RegExp.
    open.lastIndex = start

  # Append any remaining template to the buffer.
  buffer.push(template[start..end]) if start < end

  # Cache the buffer for future calls.
  TemplateCache[subtemplate] = buffer

  return buffer

escape = (value) ->
  return value.replace(/&/, '&amp;').
               replace(/"/, '&quot;').
               replace(/</, '&lt;').
               replace(/>/, '&gt;')

find = (name, stack) ->
  for i in [stack.length - 1...-1]
    ctx = stack[i]
    continue unless name of ctx
    value = ctx[name]
    return switch typeof value
      when 'undefined' then ''
      when 'function'  then value()
      else value.toString()
  return ''

handle = (part, context) ->
  return part if typeof part is 'string'
  switch part[0]
    when 'partial'
      [_, indent, partial] = part
      content = (handle p, context for p in partial).join('')
      content = content.replace(/^(?=.)/gm, indent) if indent
      content
    when 'unescaped' then find(part[1], context)
    when 'escaped' then escape(find(part[1], context))
    else throw "Unknown tag type: #{part[0]}"

Milk =
  render: (template, data, partials = {}, context = []) ->
    [tagOpen, tagClose] = ['{{', '}}'] if context.length is 0
    Partials = partials
    parsed = Parse template
    context.push data if data
    return (handle(part, context) for part in parsed).join('')

  clearCache: (tmpl...) ->
    TemplateCache = {} unless tmpl.length
    delete TemplateCache[t] for t in tmpl
    return

if exports?
  exports[key] = Milk[key] for key of Milk
else
  this.Milk = Milk