import Foundation

/// Small, dependency-free Markdown → HTML renderer (CommonMark-ish + GitHub tables, task lists, strikethrough).
enum Markdown {
    static func toHTML(_ source: String, baseURL: URL? = nil) -> String {
        let lines = LineEnding.normalize(source)
            .components(separatedBy: "\n")
            .map { TextTools.expandTabs($0, width: 4) }
        let renderer = MarkdownRenderer(baseURL: baseURL)
        return renderer.blocks(lines, tight: false)
    }

    /// Full HTML page.
    /// - interactive: adds the script the in-app preview uses (links, content updates).
    /// - editable: makes the rendered document editable (WYSIWYG) with a formatting toolbar.
    static func page(body: String, title: String = "Preview", interactive: Bool, editable: Bool = false) -> String {
        var script = ""
        var toolbar = ""
        var articleAttrs = ""
        if interactive {
            script = "<script>" + baseScript + (editable ? editorScript : "") + "</script>"
        }
        if editable {
            articleAttrs = " contenteditable=\"true\" spellcheck=\"true\""
            toolbar = toolbarHTML
        }
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(MarkdownRenderer.escape(title))</title>
        <style>\(css)\(editable ? editorCSS : "")</style></head>
        <body>\(toolbar)<article id="content" class="markdown-body"\(articleAttrs)>\(body)</article>\(script)</body></html>
        """
    }

    private static let toolbarHTML = """
    <div id="toolbar">
    <button data-cmd="p" title="Paragraph">¶</button>
    <button data-cmd="h1" title="Heading 1">H1</button>
    <button data-cmd="h2" title="Heading 2">H2</button>
    <button data-cmd="h3" title="Heading 3">H3</button>
    <span class="sep"></span>
    <button data-cmd="bold" title="Bold (⌘B)"><b>B</b></button>
    <button data-cmd="italic" title="Italic (⌘I)"><i>I</i></button>
    <button data-cmd="strike" title="Strikethrough (⇧⌘X)"><s>S</s></button>
    <button data-cmd="code" title="Inline code (⌥⌘K)"><code>&lt;/&gt;</code></button>
    <button data-cmd="link" title="Link (⌘K)">🔗</button>
    <span class="sep"></span>
    <button data-cmd="ul" title="Bulleted list">• List</button>
    <button data-cmd="ol" title="Numbered list">1. List</button>
    <button data-cmd="task" title="Task list">☐ Task</button>
    <button data-cmd="quote" title="Quote">❝</button>
    <button data-cmd="pre" title="Code block">{ }</button>
    <button data-cmd="table" title="Insert table">▦</button>
    <button data-cmd="hr" title="Horizontal rule">―</button>
    </div>
    """

    private static let editorCSS = """
    #toolbar { position: sticky; top: 0; z-index: 10; display: flex; flex-wrap: wrap; gap: 2px; align-items: center;
               padding: 6px 10px; margin: -24px -32px 20px; background: rgba(246,248,250,.94);
               -webkit-backdrop-filter: blur(8px); border-bottom: 1px solid #d1d9e0; }
    #toolbar button { font: 13px -apple-system, sans-serif; min-width: 30px; height: 26px; padding: 0 8px;
                      border: 0; border-radius: 6px; background: none; color: inherit; }
    #toolbar button:hover { background: rgba(129,139,152,.2); }
    #toolbar button code { background: none; padding: 0; font-size: 12px; }
    #toolbar .sep { width: 1px; height: 18px; background: #d1d9e0; margin: 0 6px; }
    #content { outline: none; min-height: 70vh; caret-color: #0969da; }
    #content li.task > input { cursor: pointer; }
    @media (prefers-color-scheme: dark) {
      #toolbar { background: rgba(22,27,34,.94); border-color: #3d444d; }
      #toolbar .sep { background: #3d444d; }
      #content { caret-color: #4493f8; }
    }
    """

    /// Shared by the read-only and editable views.
    private static let baseScript = #"""
    (function () {
      var content = document.getElementById('content');
      var post = function (m) { window.webkit.messageHandlers.macpad.postMessage(m); };
      var editable = content.isContentEditable;
      window.macpadSetContent = function (html) {
        content.innerHTML = html;
        if (window.macpadPrepare) window.macpadPrepare();
      };
      document.addEventListener('click', function (e) {
        var a = e.target.closest ? e.target.closest('a') : null;
        if (!a) return;
        e.preventDefault();
        if (editable && !e.metaKey) return; // in edit mode, Cmd-click opens links
        var href = a.getAttribute('href') || '';
        if (href.charAt(0) === '#') {
          var t = document.getElementById(decodeURIComponent(href.slice(1)));
          if (t) t.scrollIntoView();
          return;
        }
        post({ type: 'link', href: a.href });
      });
      setTimeout(function () { post({ type: 'ready' }); }, 0);
    })();
    """#

    /// WYSIWYG editing + HTML -> Markdown conversion.
    private static let editorScript = #"""
    (function () {
      var content = document.getElementById('content');
      var post = function (m) { window.webkit.messageHandlers.macpad.postMessage(m); };
      var timer = null, pending = false, savedRange = null;
      document.execCommand('defaultParagraphSeparator', false, 'p');

      window.macpadPrepare = function () {
        content.querySelectorAll('input[type=checkbox]').forEach(function (c) {
          c.disabled = false;
          c.setAttribute('contenteditable', 'false');
        });
        if (!content.innerHTML.trim()) content.innerHTML = '<p><br></p>';
        pending = false;
      };
      window.macpadPrepare();

      function sync() {
        pending = true;
        clearTimeout(timer);
        timer = setTimeout(function () {
          if (!pending) return;
          pending = false;
          post({ type: 'markdown', text: toMarkdown() });
        }, 200);
      }
      window.macpadFlush = function () {
        clearTimeout(timer);
        if (!pending) return null;
        pending = false;
        return toMarkdown();
      };
      window.macpadFocus = function () { content.focus(); };

      // ---------- HTML -> Markdown ----------
      var INLINE = { A:1, ABBR:1, B:1, BR:1, CODE:1, DEL:1, EM:1, I:1, IMG:1, INPUT:1, KBD:1, MARK:1, S:1, SMALL:1,
                     SPAN:1, STRIKE:1, STRONG:1, SUB:1, SUP:1, U:1, FONT:1, LABEL:1, Q:1, CITE:1 };
      var BLOCK = { P:1, DIV:1, H1:1, H2:1, H3:1, H4:1, H5:1, H6:1, UL:1, OL:1, PRE:1, BLOCKQUOTE:1, TABLE:1, HR:1, LI:1 };

      function escText(t) {
        t = t.replace(/\u00a0/g, ' ').replace(/\\/g, '\\\\').replace(/([*`\[\]])/g, '\\$1');
        return t.replace(/_/g, function (m, off, str) {
          var a = str.charAt(off - 1) || ' ', b = str.charAt(off + 1) || ' ';
          return (/[A-Za-z0-9]/.test(a) && /[A-Za-z0-9]/.test(b)) ? '_' : '\\_';
        });
      }
      function wrap(t, m) {
        if (!t.trim()) return t;
        var lead = t.match(/^\s*/)[0], trail = t.match(/\s*$/)[0];
        return lead + m + t.trim() + m + trail;
      }
      function codeSpan(t) {
        var longest = 0;
        (t.match(/`+/g) || []).forEach(function (r) { longest = Math.max(longest, r.length); });
        var f = new Array(longest + 2).join('`');
        var pad = (t.charAt(0) === '`' || t.charAt(t.length - 1) === '`') ? ' ' : '';
        return f + pad + t + pad + f;
      }
      function inl(nodes) {
        var out = '';
        Array.prototype.forEach.call(nodes, function (n) {
          if (n.nodeType === 3) { out += escText(n.nodeValue); return; }
          if (n.nodeType !== 1) return;
          var tag = n.tagName;
          if (tag === 'STRONG' || tag === 'B') out += wrap(inl(n.childNodes), '**');
          else if (tag === 'EM' || tag === 'I') out += wrap(inl(n.childNodes), '*');
          else if (tag === 'DEL' || tag === 'S' || tag === 'STRIKE') out += wrap(inl(n.childNodes), '~~');
          else if (tag === 'CODE') out += codeSpan(n.textContent);
          else if (tag === 'A') {
            var href = n.getAttribute('href') || '';
            var text = inl(n.childNodes);
            if (n.textContent === href && /^https?:/.test(href)) out += href;
            else out += '[' + text + '](' + href.replace(/ /g, '%20') + ')';
          }
          else if (tag === 'IMG') {
            out += '![' + (n.getAttribute('alt') || '') + '](' + (n.getAttribute('data-src') || n.getAttribute('src') || '') + ')';
          }
          else if (tag === 'BR') out += '  \n';
          else if (tag === 'INPUT') { /* task checkbox: handled by the list */ }
          else out += inl(n.childNodes);
        });
        return out;
      }
      function fixLineStart(t) {
        return t.split('\n').map(function (l) {
          if (/^\d+[.)]\s/.test(l)) return l.replace(/^(\d+)([.)])/, '$1\\$2');
          if (/^(#{1,6}\s|>|[-+]\s|={3,}\s*$|-{3,}\s*$)/.test(l)) return '\\' + l;
          return l;
        }).join('\n');
      }
      function hasBlockChild(el) {
        for (var i = 0; i < el.children.length; i++) if (BLOCK[el.children[i].tagName]) return true;
        return false;
      }
      function blk(el) {
        var out = [], buf = [];
        function flush() {
          var t = inl(buf).replace(/^\s+|\s+$/g, '');
          if (t) out.push(fixLineStart(t));
          buf = [];
        }
        Array.prototype.forEach.call(el.childNodes, function (n) {
          if (n.nodeType === 3 || (n.nodeType === 1 && INLINE[n.tagName])) { buf.push(n); return; }
          if (n.nodeType !== 1) return;
          flush();
          var tag = n.tagName;
          if (/^H[1-6]$/.test(tag)) {
            var h = inl(n.childNodes).replace(/\s+/g, ' ').trim();
            if (h) out.push(new Array(+tag.charAt(1) + 1).join('#') + ' ' + h);
          } else if (tag === 'P' || tag === 'DIV' || tag === 'LI') {
            if (hasBlockChild(n)) out = out.concat(blk(n));
            else { var t = inl(n.childNodes).replace(/^\s+|\s+$/g, ''); if (t) out.push(fixLineStart(t)); }
          } else if (tag === 'BLOCKQUOTE') {
            var inner = blk(n).join('\n\n');
            out.push(inner.split('\n').map(function (l) { return l ? '> ' + l : '>'; }).join('\n'));
          } else if (tag === 'PRE') {
            var code = n.querySelector('code');
            var m = code && code.className ? code.className.match(/language-(\S+)/) : null;
            var body = (code || n).textContent.replace(/\n$/, '');
            var fence = body.indexOf('```') >= 0 ? '~~~' : '```';
            out.push(fence + (m ? m[1] : '') + '\n' + body + '\n' + fence);
          } else if (tag === 'UL' || tag === 'OL') {
            out.push(list(n));
          } else if (tag === 'HR') {
            out.push('---');
          } else if (tag === 'TABLE') {
            out.push(table(n));
          } else {
            out = out.concat(blk(n));
          }
        });
        flush();
        return out;
      }
      function list(el) {
        var ordered = el.tagName === 'OL';
        var n = parseInt(el.getAttribute('start') || '1', 10) || 1;
        var items = [], loose = false;
        Array.prototype.forEach.call(el.children, function (li) {
          if (li.tagName !== 'LI') return;
          var marker = ordered ? (n++) + '. ' : '- ';
          var cb = li.querySelector('input[type=checkbox]');
          if (cb && cb.closest('li') !== li) cb = null;
          var task = cb ? (cb.checked ? '[x] ' : '[ ] ') : '';
          var paras = 0;
          for (var i = 0; i < li.children.length; i++) if (li.children[i].tagName === 'P') paras++;
          if (paras > 1) loose = true;
          var parts = blk(li);
          var bodyText = parts.join(paras > 1 ? '\n\n' : '\n');
          var pad = new Array(marker.length + 1).join(' ');
          items.push(bodyText.split('\n').map(function (l, k) {
            return k === 0 ? marker + task + l : (l ? pad + l : '');
          }).join('\n'));
        });
        return items.join(loose ? '\n\n' : '\n');
      }
      function table(el) {
        var rows = el.querySelectorAll('tr');
        if (!rows.length) return '';
        function cells(r) {
          return Array.prototype.map.call(r.children, function (c) {
            return inl(c.childNodes).replace(/\s*\n\s*/g, ' ').trim().replace(/\|/g, '\\|');
          });
        }
        var head = cells(rows[0]);
        var aligns = Array.prototype.map.call(rows[0].children, function (c) {
          var a = (c.getAttribute('style') || '').match(/text-align:\s*(\w+)/);
          var v = a ? a[1] : '';
          return v === 'center' ? ':---:' : v === 'right' ? '---:' : v === 'left' ? ':---' : '---';
        });
        var out = '| ' + head.join(' | ') + ' |\n| ' + aligns.join(' | ') + ' |';
        for (var i = 1; i < rows.length; i++) {
          var c = cells(rows[i]);
          while (c.length < head.length) c.push('');
          out += '\n| ' + c.join(' | ') + ' |';
        }
        return out;
      }
      function toMarkdown() {
        return blk(content).join('\n\n').replace(/\n{3,}/g, '\n\n').replace(/^\s+|\s+$/g, '') + '\n';
      }
      window.macpadMarkdown = toMarkdown;

      // ---------- Editing commands ----------
      function blockOf(node) {
        while (node && node !== content) {
          if (node.nodeType === 1 && node.parentNode === content) return node;
          if (node.nodeType === 1 && /^(LI|P|DIV|H[1-6]|PRE|BLOCKQUOTE)$/.test(node.tagName)) return node;
          node = node.parentNode;
        }
        return null;
      }
      function currentLI() {
        var s = getSelection();
        if (!s.rangeCount) return null;
        var n = s.anchorNode;
        while (n && n !== content) { if (n.nodeType === 1 && n.tagName === 'LI') return n; n = n.parentNode; }
        return null;
      }
      function askLink() {
        var s = getSelection();
        savedRange = s.rangeCount ? s.getRangeAt(0).cloneRange() : null;
        var el = s.anchorNode ? (s.anchorNode.nodeType === 1 ? s.anchorNode : s.anchorNode.parentElement) : null;
        var a = el ? el.closest('a') : null;
        post({ type: 'askLink', text: s.toString(), href: a ? a.getAttribute('href') : '' });
      }
      window.macpadApplyLink = function (url) {
        content.focus();
        var s = getSelection();
        if (savedRange) { s.removeAllRanges(); s.addRange(savedRange); }
        if (!url) { document.execCommand('unlink'); sync(); return; }
        if (s.isCollapsed) {
          var a = document.createElement('a');
          a.href = url; a.textContent = url;
          document.execCommand('insertHTML', false, a.outerHTML);
        } else {
          document.execCommand('createLink', false, url);
        }
        sync();
      };
      function toggleInlineCode() {
        var s = getSelection();
        if (!s.rangeCount) return;
        var n = s.anchorNode;
        var el = n ? (n.nodeType === 1 ? n : n.parentElement) : null;
        var codeEl = el ? el.closest('code') : null;
        if (codeEl && !codeEl.closest('pre')) {
          codeEl.parentNode.replaceChild(document.createTextNode(codeEl.textContent), codeEl);
          return;
        }
        var r = s.getRangeAt(0);
        var c = document.createElement('code');
        c.textContent = r.toString() || 'code';
        r.deleteContents();
        r.insertNode(c);
        var nr = document.createRange();
        nr.selectNodeContents(c);
        s.removeAllRanges(); s.addRange(nr);
      }
      function makeTask() {
        if (!currentLI()) document.execCommand('insertUnorderedList');
        var li = currentLI();
        if (!li) return;
        var existing = li.querySelector('input[type=checkbox]');
        if (existing && existing.closest('li') === li) { existing.remove(); li.classList.remove('task'); return; }
        var cb = document.createElement('input');
        cb.type = 'checkbox';
        cb.setAttribute('contenteditable', 'false');
        li.classList.add('task');
        li.insertBefore(document.createTextNode(' '), li.firstChild);
        li.insertBefore(cb, li.firstChild);
      }
      window.macpadCmd = function (name) {
        content.focus();
        switch (name) {
          case 'bold': document.execCommand('bold'); break;
          case 'italic': document.execCommand('italic'); break;
          case 'strike': document.execCommand('strikeThrough'); break;
          case 'h1': case 'h2': case 'h3': case 'h4': case 'h5': case 'h6': case 'p': case 'pre':
            document.execCommand('formatBlock', false, name); break;
          case 'quote': document.execCommand('formatBlock', false, 'blockquote'); break;
          case 'ul': document.execCommand('insertUnorderedList'); break;
          case 'ol': document.execCommand('insertOrderedList'); break;
          case 'task': makeTask(); break;
          case 'code': toggleInlineCode(); break;
          case 'hr': document.execCommand('insertHorizontalRule'); break;
          case 'link': askLink(); return;
          case 'table':
            document.execCommand('insertHTML', false,
              '<table><thead><tr><th>Column 1</th><th>Column 2</th></tr></thead>' +
              '<tbody><tr><td>&nbsp;</td><td>&nbsp;</td></tr></tbody></table><p><br></p>');
            break;
          case 'undo': document.execCommand('undo'); break;
          case 'redo': document.execCommand('redo'); break;
        }
        sync();
      };

      document.getElementById('toolbar').addEventListener('mousedown', function (e) {
        var b = e.target.closest('button');
        if (!b) return;
        e.preventDefault();
        window.macpadCmd(b.getAttribute('data-cmd'));
      });

      // Task checkboxes
      content.addEventListener('click', function (e) {
        var t = e.target;
        if (t.tagName === 'INPUT' && t.type === 'checkbox') {
          e.preventDefault();
          var now = !t.hasAttribute('checked');
          setTimeout(function () {
            t.checked = now;
            if (now) t.setAttribute('checked', ''); else t.removeAttribute('checked');
            sync();
          }, 0);
        }
      });

      // Tab / Shift-Tab nests list items
      content.addEventListener('keydown', function (e) {
        if (e.key === 'Tab' && currentLI()) {
          e.preventDefault();
          document.execCommand(e.shiftKey ? 'outdent' : 'indent');
          sync();
        }
      });

      // Markdown typing shortcuts at the start of a paragraph: "# ", "## ", "- ", "* ", "1. ", "> ", "[] "
      function autoFormat() {
        var s = getSelection();
        if (!s.rangeCount || !s.isCollapsed) return;
        var block = blockOf(s.anchorNode);
        if (!block || !/^(P|DIV)$/.test(block.tagName)) return;
        var r = document.createRange();
        r.selectNodeContents(block);
        r.setEnd(s.anchorNode, s.anchorOffset);
        var before = r.toString().replace(/\u00a0/g, ' ');
        var m = before.match(/^(#{1,6}|[-*+]|1[.)]|>|\[ ?\]) $/);
        if (!m) return;
        for (var i = 0; i < before.length; i++) s.modify('extend', 'backward', 'character');
        document.execCommand('delete');
        var k = m[1];
        if (k.charAt(0) === '#') document.execCommand('formatBlock', false, 'h' + k.length);
        else if (k === '>') document.execCommand('formatBlock', false, 'blockquote');
        else if (/^\d/.test(k)) document.execCommand('insertOrderedList');
        else if (k.charAt(0) === '[') makeTask();
        else document.execCommand('insertUnorderedList');
      }
      content.addEventListener('input', function (e) {
        if (e.inputType === 'insertText' && e.data === ' ') autoFormat();
        sync();
      });
    })();
    """#

    /// JSON string literal (safe to embed in JavaScript).
    static func jsonString(_ s: String) -> String {
        if let data = try? JSONEncoder().encode(s), let str = String(data: data, encoding: .utf8) { return str }
        return "\"\""
    }

    static let css = """
    :root { color-scheme: light dark; }
    body { font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
           margin: 0; padding: 24px 32px 64px; color: #1f2328; background: #ffffff; word-wrap: break-word; }
    .markdown-body { max-width: 880px; margin: 0 auto; }
    h1, h2, h3, h4, h5, h6 { margin: 24px 0 16px; font-weight: 600; line-height: 1.25; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid #d1d9e0; }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid #d1d9e0; }
    h3 { font-size: 1.25em; } h4 { font-size: 1em; } h5 { font-size: .875em; } h6 { font-size: .85em; color: #59636e; }
    p, blockquote, ul, ol, table, pre, dl { margin: 0 0 16px; }
    a { color: #0969da; text-decoration: none; } a:hover { text-decoration: underline; }
    code { font: 85% ui-monospace, SFMono-Regular, Menlo, monospace; background: rgba(129,139,152,.15);
           padding: .2em .4em; border-radius: 6px; }
    pre { background: #f6f8fa; padding: 16px; border-radius: 6px; overflow: auto; line-height: 1.45; }
    pre code { background: none; padding: 0; font-size: 85%; }
    blockquote { padding: 0 1em; color: #59636e; border-left: .25em solid #d1d9e0; margin-left: 0; margin-right: 0; }
    ul, ol { padding-left: 2em; } li + li { margin-top: .25em; } li > ul, li > ol { margin-bottom: 0; }
    li.task { list-style: none; } li.task > input { margin: 0 .4em 0 -1.5em; vertical-align: middle; }
    table { border-collapse: collapse; display: block; width: max-content; max-width: 100%; overflow: auto; }
    th, td { border: 1px solid #d1d9e0; padding: 6px 13px; } th { font-weight: 600; }
    tr:nth-child(2n) { background: #f6f8fa; }
    hr { height: .25em; border: 0; background: #d1d9e0; margin: 24px 0; }
    img { max-width: 100%; }
    del { opacity: .7; }
    @media (prefers-color-scheme: dark) {
      body { color: #e6edf3; background: #0d1117; }
      a { color: #4493f8; }
      pre { background: #161b22; }
      blockquote, h6 { color: #9198a1; }
      blockquote, h1, h2, th, td { border-color: #3d444d; }
      hr { background: #3d444d; }
      tr:nth-child(2n) { background: #151b23; }
    }
    """
}

final class MarkdownRenderer {
    private let baseURL: URL?
    private var placeholders: [String] = []

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    // MARK: - Regex helpers

    private static func re(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants; a failure is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    private static let headingRE = re(#"^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$"#)
    private static let fenceRE = re(#"^( {0,3})(`{3,}|~{3,})[ \t]*([^`\s]*)"#)
    private static let hrRE = re(#"^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$"#)
    private static let listRE = re(#"^( *)([-*+]|\d{1,9}[.)])(?:( +)(.*))?$"#)
    private static let quoteRE = re(#"^ {0,3}> ?(.*)$"#)
    private static let tableSepRE = re(#"^ *\|? *:?-+:? *(?:\| *:?-+:? *)*\|? *$"#)
    private static let htmlBlockRE = re(#"^ {0,3}<(?:[A-Za-z][A-Za-z0-9-]*[\s/>]|[A-Za-z][A-Za-z0-9-]*$|/[A-Za-z]|!--)"#)
    private static let setext1RE = re(#"^ {0,3}=+ *$"#)
    private static let setext2RE = re(#"^ {0,3}-+ *$"#)
    private static let taskRE = re(#"^\[([ xX])\][ \t]+(.*)$"#)

    private static let codeSpanRE = re(#"(`+)([\s\S]+?)(?<!`)\1(?!`)"#)
    private static let escapeRE = re(##"\\([!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~])"##)
    private static let autolinkRE = re(#"<((?:https?|mailto|ftp):[^<>\s]+)>"#)
    private static let imageRE = re(#"!\[([^\]]*)\]\(\s*<?([^\s)>]+)>?(?:\s+["']([^"']*)["'])?\s*\)"#)
    private static let linkRE = re(#"\[((?:[^\[\]]|\[[^\[\]]*\])*)\]\(\s*<?([^\s)>]*)>?(?:\s+["']([^"']*)["'])?\s*\)"#)
    private static let htmlTagRE = re(#"<!--[\s\S]*?-->|</?[A-Za-z][A-Za-z0-9-]*(?:\s+[^<>]*)?/?>"#)
    private static let bareURLRE = re(#"(?<![\w/"'=])(?:https?://|www\.)[^\s<>"\x{1A}]+[^\s<>"\x{1A}.,;:!?)\]'*_]"#)
    private static let boldRE = re(#"\*\*(?=\S)([\s\S]+?)(?<=\S)\*\*|(?<!\w)__(?=\S)([\s\S]+?)(?<=\S)__(?!\w)"#)
    private static let italicRE = re(#"(?<![*\w])\*(?=[^\s*])([\s\S]+?)(?<=[^\s*])\*(?![*\w])|(?<![_\w])_(?=[^\s_])([\s\S]+?)(?<=[^\s_])_(?![_\w])"#)
    private static let strikeRE = re(#"~~(?=\S)([\s\S]+?)(?<=\S)~~"#)
    private static let placeholderRE = re("\u{1A}(\\d+)\u{1A}")

    private static func groups(_ re: NSRegularExpression, _ s: String) -> [String?]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { k in
            let r = m.range(at: k)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    private static func substitute(_ s: String, _ re: NSRegularExpression, _ transform: ([String]) -> String) -> String {
        let ns = s as NSString
        let found = re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
        if found.isEmpty { return s }
        var out = ""
        var last = 0
        for m in found {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let g: [String] = (0..<m.numberOfRanges).map { k in
                let r = m.range(at: k)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            out += transform(g)
            last = NSMaxRange(m.range)
        }
        out += ns.substring(from: last)
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func isBlank(_ s: String) -> Bool {
        s.allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func leadingSpaces(_ s: String) -> Int {
        s.prefix { $0 == " " }.count
    }

    private static func trimLeading(_ s: String) -> String {
        String(s.drop { $0 == " " || $0 == "\t" })
    }

    static func slug(_ text: String) -> String {
        var out = ""
        for c in text.lowercased() {
            if c.isLetter || c.isNumber || c == "-" || c == "_" { out.append(c) }
            else if c == " " { out.append("-") }
        }
        return out
    }

    // MARK: - Lists

    private struct ListMarker {
        let indent: Int
        let ordered: Bool
        let start: Int
        let contentOffset: Int
        let text: String
    }

    private static func listMarker(_ line: String) -> ListMarker? {
        guard !matches(hrRE, line), let g = groups(listRE, line) else { return nil }
        let indent = g[1]?.count ?? 0
        let marker = g[2] ?? "-"
        let spaces = g[3]?.count ?? 1
        let text = g[4] ?? ""
        let ordered = marker.first?.isNumber ?? false
        let start = ordered ? (Int(marker.dropLast()) ?? 1) : 1
        let gap = (spaces > 4 || text.isEmpty) ? 1 : spaces
        let body = spaces > 4 ? String(repeating: " ", count: spaces - 1) + text : text
        return ListMarker(indent: indent, ordered: ordered, start: start, contentOffset: indent + marker.count + gap, text: body)
    }

    private static func startsBlock(_ line: String) -> Bool {
        if matches(headingRE, line) || matches(fenceRE, line) || matches(hrRE, line) || matches(quoteRE, line) { return true }
        if let m = listMarker(line), !m.text.isEmpty, !m.ordered || m.start == 1 { return true }
        return false
    }

    // MARK: - Blocks

    func blocks(_ lines: [String], tight: Bool) -> String {
        typealias R = MarkdownRenderer
        var out = ""
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if R.isBlank(line) { i += 1; continue }

            // Fenced code
            if let g = R.groups(R.fenceRE, line), let fence = g[2], let fenceChar = fence.first {
                let indent = g[1]?.count ?? 0
                let lang = g[3] ?? ""
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let l = lines[i]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.count >= fence.count && t.allSatisfy({ $0 == fenceChar }) { i += 1; break }
                    code.append(String(l.dropFirst(min(indent, R.leadingSpaces(l)))))
                    i += 1
                }
                let cls = lang.isEmpty ? "" : " class=\"language-\(R.escape(lang))\""
                let body = code.isEmpty ? "" : R.escape(code.joined(separator: "\n")) + "\n"
                out += "<pre><code\(cls)>\(body)</code></pre>\n"
                continue
            }

            // ATX heading
            if let g = R.groups(R.headingRE, line) {
                let level = g[1]?.count ?? 1
                let text = g[2] ?? ""
                out += "<h\(level) id=\"\(R.escape(R.slug(text)))\">\(inline(text))</h\(level)>\n"
                i += 1
                continue
            }

            if R.matches(R.hrRE, line) { out += "<hr>\n"; i += 1; continue }

            // Blockquote
            if R.matches(R.quoteRE, line) {
                var inner: [String] = []
                while i < lines.count {
                    if let g = R.groups(R.quoteRE, lines[i]) {
                        inner.append(g[1] ?? "")
                    } else if !R.isBlank(lines[i]), let last = inner.last, !R.isBlank(last), !R.startsBlock(lines[i]) {
                        inner.append(lines[i]) // lazy continuation
                    } else {
                        break
                    }
                    i += 1
                }
                out += "<blockquote>\n" + blocks(inner, tight: false) + "</blockquote>\n"
                continue
            }

            // List
            if R.listMarker(line) != nil {
                out += list(lines, &i)
                continue
            }

            // Indented code
            if R.leadingSpaces(line) >= 4 {
                var code: [String] = []
                while i < lines.count && (R.isBlank(lines[i]) || R.leadingSpaces(lines[i]) >= 4) {
                    code.append(String(lines[i].dropFirst(min(4, R.leadingSpaces(lines[i])))))
                    i += 1
                }
                while let last = code.last, R.isBlank(last) { code.removeLast() }
                out += "<pre><code>" + R.escape(code.joined(separator: "\n")) + "\n</code></pre>\n"
                continue
            }

            // Table
            if i + 1 < lines.count, line.contains("|"), lines[i + 1].contains("-"), R.matches(R.tableSepRE, lines[i + 1]) {
                out += table(lines, &i)
                continue
            }

            // Raw HTML block
            if R.matches(R.htmlBlockRE, line) {
                while i < lines.count && !R.isBlank(lines[i]) {
                    out += lines[i] + "\n"
                    i += 1
                }
                continue
            }

            // Paragraph (or setext heading)
            var para: [String] = [R.trimLeading(line)]
            var setext: Int?
            i += 1
            while i < lines.count {
                let l = lines[i]
                if R.isBlank(l) { break }
                if R.matches(R.setext1RE, l) { setext = 1; i += 1; break }
                if R.matches(R.setext2RE, l) { setext = 2; i += 1; break }
                if R.startsBlock(l) { break }
                if i + 1 < lines.count, l.contains("|"), lines[i + 1].contains("-"), R.matches(R.tableSepRE, lines[i + 1]) { break }
                para.append(R.trimLeading(l))
                i += 1
            }
            let content = inlineLines(para)
            if let level = setext {
                let plain = para.joined(separator: " ")
                out += "<h\(level) id=\"\(R.escape(R.slug(plain)))\">\(content)</h\(level)>\n"
            } else if tight {
                out += content + "\n"
            } else {
                out += "<p>\(content)</p>\n"
            }
        }
        return out
    }

    private func list(_ lines: [String], _ i: inout Int) -> String {
        typealias R = MarkdownRenderer
        guard let first = R.listMarker(lines[i]) else { return "" }
        var items: [[String]] = []
        var current: [String] = [first.text]
        var contentIndent = first.contentOffset
        var loose = false
        i += 1

        while i < lines.count {
            let l = lines[i]
            if R.isBlank(l) {
                var j = i + 1
                while j < lines.count && R.isBlank(lines[j]) { j += 1 }
                guard j < lines.count else { break }
                let next = lines[j]
                if R.leadingSpaces(next) >= contentIndent {
                    current.append(contentsOf: Array(repeating: "", count: j - i))
                    loose = true
                    i = j
                    continue
                }
                if let m = R.listMarker(next), m.indent < contentIndent, m.ordered == first.ordered {
                    loose = true
                    i = j
                    continue
                }
                break
            }
            if let m = R.listMarker(l), m.indent < contentIndent {
                if m.ordered != first.ordered { break }
                items.append(current)
                current = [m.text]
                contentIndent = m.contentOffset
                i += 1
                continue
            }
            if R.leadingSpaces(l) >= contentIndent {
                current.append(String(l.dropFirst(contentIndent)))
                i += 1
                continue
            }
            if !R.startsBlock(l), let last = current.last, !R.isBlank(last) {
                current.append(R.trimLeading(l)) // lazy continuation
                i += 1
                continue
            }
            break
        }
        items.append(current)

        var out = first.ordered ? (first.start != 1 ? "<ol start=\"\(first.start)\">\n" : "<ol>\n") : "<ul>\n"
        for var item in items {
            var checkbox = ""
            var cls = ""
            if let firstLine = item.first, let g = R.groups(R.taskRE, firstLine) {
                let checked = (g[1] ?? " ") != " "
                checkbox = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")> "
                cls = " class=\"task\""
                item[0] = g[2] ?? ""
            }
            var inner = blocks(item, tight: !loose)
            while inner.hasSuffix("\n") { inner.removeLast() }
            if !checkbox.isEmpty {
                if inner.hasPrefix("<p>") {
                    inner = "<p>" + checkbox + inner.dropFirst(3)
                } else {
                    inner = checkbox + inner
                }
            }
            out += "<li\(cls)>\(inner)</li>\n"
        }
        out += first.ordered ? "</ol>\n" : "</ul>\n"
        return out
    }

    private func table(_ lines: [String], _ i: inout Int) -> String {
        typealias R = MarkdownRenderer
        func cells(_ line: String) -> [String] {
            var s = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "\u{1C}")
            if s.hasPrefix("|") { s.removeFirst() }
            if s.hasSuffix("|") { s.removeLast() }
            return s.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{1C}", with: "|")
            }
        }
        let header = cells(lines[i])
        let aligns: [String] = cells(lines[i + 1]).map { c in
            let left = c.hasPrefix(":"), right = c.hasSuffix(":")
            if left && right { return " style=\"text-align:center\"" }
            if right { return " style=\"text-align:right\"" }
            if left { return " style=\"text-align:left\"" }
            return ""
        }
        func align(_ k: Int) -> String { k < aligns.count ? aligns[k] : "" }
        i += 2

        var out = "<table>\n<thead>\n<tr>"
        for (k, cell) in header.enumerated() { out += "<th\(align(k))>\(inline(cell))</th>" }
        out += "</tr>\n</thead>\n<tbody>\n"
        while i < lines.count, !R.isBlank(lines[i]), lines[i].contains("|") {
            let row = cells(lines[i])
            out += "<tr>"
            for k in 0..<header.count {
                out += "<td\(align(k))>\(k < row.count ? inline(row[k]) : "")</td>"
            }
            out += "</tr>\n"
            i += 1
        }
        out += "</tbody>\n</table>\n"
        return out
    }

    // MARK: - Inline

    private func protect(_ html: String) -> String {
        placeholders.append(html)
        return "\u{1A}\(placeholders.count - 1)\u{1A}"
    }

    /// Joins paragraph lines, turning "two trailing spaces" / trailing backslash into <br>.
    private func inlineLines(_ lines: [String]) -> String {
        var parts: [String] = []
        for (k, line) in lines.enumerated() {
            let isLast = k == lines.count - 1
            if !isLast && line.hasSuffix("  ") {
                parts.append(TextTools.trimEnd(line) + "\u{1B}")
            } else if !isLast && line.hasSuffix("\\") {
                parts.append(String(line.dropLast()) + "\u{1B}")
            } else {
                parts.append(TextTools.trimEnd(line))
            }
        }
        return inline(parts.joined(separator: "\n")).replacingOccurrences(of: "\u{1B}", with: "<br>")
    }

    func inline(_ text: String, allowLinks: Bool = true) -> String {
        typealias R = MarkdownRenderer
        var s = text

        s = R.substitute(s, R.codeSpanRE) { g in
            var code = g[2]
            if code.count > 2, code.hasPrefix(" "), code.hasSuffix(" ") { code = String(code.dropFirst().dropLast()) }
            return self.protect("<code>" + R.escape(code) + "</code>")
        }
        s = R.substitute(s, R.escapeRE) { g in self.protect(R.escape(g[1])) }
        s = R.substitute(s, R.autolinkRE) { g in
            self.protect("<a href=\"\(R.escape(g[1]))\">\(R.escape(g[1]))</a>")
        }
        s = R.substitute(s, R.imageRE) { g in
            let title = g[3].isEmpty ? "" : " title=\"\(R.escape(g[3]))\""
            return self.protect("<img src=\"\(R.escape(self.imageSource(g[2])))\" data-src=\"\(R.escape(g[2]))\" alt=\"\(R.escape(g[1]))\"\(title)>")
        }
        if allowLinks {
            s = R.substitute(s, R.linkRE) { g in
                let title = g[3].isEmpty ? "" : " title=\"\(R.escape(g[3]))\""
                let label = self.inline(g[1], allowLinks: false)
                return self.protect("<a href=\"\(R.escape(g[2]))\"\(title)>\(label)</a>")
            }
        }
        s = R.substitute(s, R.htmlTagRE) { g in self.protect(g[0]) }
        if allowLinks {
            s = R.substitute(s, R.bareURLRE) { g in
                let href = g[0].hasPrefix("www.") ? "https://" + g[0] : g[0]
                return self.protect("<a href=\"\(R.escape(href))\">\(R.escape(g[0]))</a>")
            }
        }

        s = R.escape(s)
        s = R.substitute(s, R.boldRE) { g in "<strong>\(g[1])\(g[2])</strong>" }
        s = R.substitute(s, R.italicRE) { g in "<em>\(g[1])\(g[2])</em>" }
        s = R.substitute(s, R.strikeRE) { g in "<del>\(g[1])</del>" }

        for _ in 0..<5 where s.contains("\u{1A}") {
            s = R.substitute(s, R.placeholderRE) { g in
                guard let n = Int(g[1]), self.placeholders.indices.contains(n) else { return "" }
                return self.placeholders[n]
            }
        }
        return s
    }

    // MARK: - Local images → data URLs (the preview can't read files directly)

    private static var imageCache: [String: (Date?, String)] = [:]

    private func imageSource(_ src: String) -> String {
        let lower = src.lowercased()
        if lower.hasPrefix("http:") || lower.hasPrefix("https:") || lower.hasPrefix("data:") { return src }
        let url: URL?
        if lower.hasPrefix("file:") {
            url = URL(string: src)
        } else if let base = baseURL {
            url = URL(fileURLWithPath: src.removingPercentEncoding ?? src, relativeTo: base)
        } else {
            url = nil
        }
        guard let fileURL = url?.standardizedFileURL else { return src }
        let path = fileURL.path
        let modified = FileIO.modificationDate(fileURL)
        if let cached = MarkdownRenderer.imageCache[path], cached.0 == modified { return cached.1 }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber, size.intValue < 15_000_000,
              let data = try? Data(contentsOf: fileURL) else { return src }
        let mime: String
        switch fileURL.pathExtension.lowercased() {
        case "png": mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        case "gif": mime = "image/gif"
        case "svg": mime = "image/svg+xml"
        case "webp": mime = "image/webp"
        case "bmp": mime = "image/bmp"
        case "ico": mime = "image/x-icon"
        default: return src
        }
        let result = "data:\(mime);base64,\(data.base64EncodedString())"
        MarkdownRenderer.imageCache[path] = (modified, result)
        return result
    }
}
