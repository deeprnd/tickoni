#!/usr/bin/env python3
"""Convert Zig release-notes.html to clean Markdown."""
import re
from html.parser import HTMLParser

with open('/home/vicgenin/work/git/tickoni/doc/knowledge/zig/release-notes.html', 'r') as f:
    html = f.read()

# Step 1: Extract body content
start = html.index('<div id="contents">') + len('<div id="contents">')
depth = 1
i = start
while i < len(html) and depth > 0:
    if html[i:i+6] == '</div>':
        depth -= 1
    elif html[i:i+5] == '<div ':
        depth += 1
    i += 1
html = html[start:i]

# Step 2: Strip CSS and comments
html = re.sub(r'\s*style="[^"]*"', '', html)
html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL)
html = re.sub(r'\s+class="[^"]*"', '', html)
html = re.sub(r'<!--.*?-->', '', html, flags=re.DOTALL)

# Step 3: Replace wiki-link placeholders
wiki_links = []

def replace_wiki(m):
    idx = len(wiki_links)
    link_type = m.group(1)
    rest = m.group(2)
    wiki_links.append((link_type, rest))
    return f'__WIKI_{idx}__'

# Pipe-separated wiki links - use non-greedy match up to #}, allow newlines in text
html = re.sub(r'\{#(\w+)\|(.*?)\#\}', replace_wiki, html, flags=re.DOTALL)
# Standalone markers (no pipe)
def replace_standalone(m):
    idx = len(wiki_links)
    wiki_links.append(('standalone', m.group(1)))
    return f'__WIKI_{idx}__'
html = re.sub(r'\{#(\w+)#\}', replace_standalone, html)

print(f"Found {len(wiki_links)} wiki links total")

# Step 4: HTML -> Markdown
class MDConverter(HTMLParser):
    def __init__(self):
        super().__init__()
        self.out = []
        self.in_code = False
        self.code_buf = []
        self.in_link = False
        self.link_url = ''
        self.link_text = ''
        self.in_table = False
        self.table_header = []
        self.table_rows = []
        self.current_row = []
        self.current_cell = []
        self.in_cell = False
        self.in_thead = False
        self.in_tbody = False
        self.skip_content = False

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        d = dict(attrs)
        if tag == 'h1': self.out.append('\n# ')
        elif tag == 'h2': self.out.append('\n## ')
        elif tag == 'h3': self.out.append('\n### ')
        elif tag == 'h4': self.out.append('\n#### ')
        elif tag == 'h5': self.out.append('\n##### ')
        elif tag == 'h6': self.out.append('\n###### ')
        elif tag == 'p': self.out.append('\n\n')
        elif tag == 'li': self.out.append('\n- ')
        elif tag == 'br': self.out.append('\n')
        elif tag == 'hr':
            if not self.in_cell:
                self.out.append('\n---\n')
        elif tag == 'ul': self.out.append('\n')
        elif tag == 'ol': self.out.append('\n')
        elif tag == 'code':
            self.in_code = True
            self.code_buf = []
        elif tag == 'pre': self.skip_content = True
        elif tag == 'span':
            # Tooltip spans - keep content, strip title attribute
            pass
        elif tag == 'a':
            self.in_link = True
            self.link_url = d.get('href', '')
            self.link_text = ''
        elif tag == 'table':
            self.in_table = True
            self.table_header = []
            self.table_rows = []
            self.in_thead = False
            self.in_tbody = False
        elif tag == 'thead': self.in_thead = True
        elif tag == 'tbody': self.in_tbody = True
        elif tag == 'tr': self.current_row = []
        elif tag == 'th':
            self.in_cell = True
            self.current_cell = []
        elif tag == 'td':
            self.in_cell = True
            self.current_cell = []

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag in ('h1','h2','h3','h4','h5','h6'):
            pass
        elif tag == 'p':
            self.out.append('\n\n')
        elif tag == 'li':
            self.out.append('\n')
        elif tag == 'ul' or tag == 'ol':
            self.out.append('\n')
        elif tag == 'code':
            self.in_code = False
            txt = ''.join(self.code_buf).strip()
            # Wrap in backticks if in a cell, otherwise just output
            if self.in_cell:
                self.current_cell.append(f'`{txt}`')
            else:
                self.out.append(f'`{txt}`')
        elif tag == 'a':
            self.in_link = False
            txt = self.link_text.strip()
            if self.in_cell:
                self.current_cell.append(txt)
            elif self.link_url and txt:
                self.out.append(f'[{txt}]({self.link_url})')
            elif txt:
                self.out.append(txt)
            self.link_url = ''
            self.link_text = ''
        elif tag == 'pre':
            self.skip_content = False
        elif tag == 'th':
            self.in_cell = False
            txt = ''.join(self.current_cell).strip()
            if self.in_thead:
                self.table_header.append(txt)
            elif self.in_tbody:
                self.current_row.append(txt)
        elif tag == 'td':
            self.in_cell = False
            txt = ''.join(self.current_cell).strip()
            if self.in_tbody:
                self.current_row.append(txt)
        elif tag == 'tr':
            if self.in_tbody and self.current_row:
                self.table_rows.append(self.current_row)
        elif tag == 'table':
            if self.table_header:
                lines = []
                lines.append('| ' + ' | '.join(self.table_header) + ' |')
                lines.append('| ' + ' | '.join(['---'] * len(self.table_header)) + ' |')
                for row in self.table_rows:
                    if not any(c.strip() for c in row):
                        continue
                    while len(row) < len(self.table_header):
                        row.append('')
                    lines.append('| ' + ' | '.join(row) + ' |')
                self.out.append('\n' + '\n'.join(lines) + '\n')

    def handle_data(self, data):
        if self.skip_content:
            return
        if self.in_link:
            self.link_text += data
        elif self.in_code:
            self.code_buf.append(data)
        elif self.in_cell:
            self.current_cell.append(data)
        else:
            self.out.append(data)

converter = MDConverter()
converter.feed(html)
md = ''.join(converter.out)

# Step 5: Resolve wiki-link placeholders
def resolve_wiki(m):
    idx = int(m.group(1))
    if idx >= len(wiki_links):
        return f'__WIKI_{idx}__'
    lt, rest = wiki_links[idx]
    parts = rest.split('|')
    if lt == 'link':
        if len(parts) == 2:
            return f'[{parts[0]}](#{parts[1]})'
        return f'[{parts[0]}](#{parts[-1] if len(parts) > 1 else parts[0]})'
    elif lt == 'header_open':
        return f'\n## {parts[0]}\n'
    elif lt in ('standalone', 'header_close', 'syntax_block', 'code', 'nav', 'endsyntax', 'syntax', 'end_syntax_block'):
        return ''
    return f'__WIKI_{idx}__'

md = re.sub(r'__WIKI_(\d+)__', resolve_wiki, md)

# Step 6: Strip remaining <code> tags from output
md = re.sub(r'<code>(.*?)</code>', r'\1', md)

# Step 7: Merge orphaned "- " markers with their content
lines = md.split('\n')
merged = []
skip_next = False
for i, line in enumerate(lines):
    if skip_next:
        skip_next = False
        continue
    if line == '- ' and i + 1 < len(lines) and lines[i + 1].strip():
        merged.append('- ' + lines[i + 1].strip())
        skip_next = True
    else:
        merged.append(line)
lines = merged

# Step 8: Clean up whitespace
cleaned = []
for line in lines:
    if line.strip():
        stripped = line.lstrip()
        if stripped.startswith('|') or stripped.startswith('```'):
            cleaned.append(line)
        elif stripped.startswith('- '):
            cleaned.append(stripped)
        elif stripped.startswith('#'):
            cleaned.append(stripped)
        else:
            cleaned.append(stripped)
    else:
        cleaned.append('')

md = '\n'.join(cleaned)
md = re.sub(r'\n{4,}', '\n\n\n', md)
md = md.strip() + '\n'

output_path = '/home/vicgenin/work/git/tickoni/doc/knowledge/zig/release-notes-0.16.md'
with open(output_path, 'w') as f:
    f.write(md)

print(f"Written {len(md)} chars, {md.count(chr(10))} lines")

# Verification
headers = re.findall(r'^## .+$', md, re.MULTILINE)
print(f"## headings: {len(headers)}")
for h in headers[:10]:
    print(f"  {h}")

table_rows = [l for l in md.split('\n') if l.strip().startswith('|')]
print(f"\nTable rows: {len(table_rows)}")
print("First 3 rows:")
for l in table_rows[:4]:
    print(f"  {l}")

list_items = [l for l in md.split('\n') if l.strip().startswith('- ')]
print(f"\nList items: {len(list_items)}")
print("First 2:")
for l in list_items[:2]:
    print(f"  {l[:200]}")

# Check no wiki links remain
remaining = re.findall(r'\{#[a-zA-Z_]+\|[^}]*\#\}', md) + re.findall(r'\{#[a-zA-Z_]+#\}', md)
print(f"\nRemaining wiki links: {len(remaining)}")
