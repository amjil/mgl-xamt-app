/**
 * Native Mongolian Rich Text Editor
 * Pure vanilla JS — no external dependencies; import directly
 *
 * Blocks use a nested tree structure:
 *   .block-wrapper[data-block-type]
 *     ├─ .block-content[contenteditable]   editable content
 *     └─ .block-children                   child block container (created on demand)
 */

export function createMongolianEditor(containerSelector) {
    const container = typeof containerSelector === 'string' ? document.querySelector(containerSelector) : containerSelector;
    if (!container) {
        console.error('Editor container not found!');
        return;
    }

    // ==========================================
    // 1. Inject CSS (once globally)
    // ==========================================
    if (!document.getElementById('mgl-editor-style')) {
        const style = document.createElement('style');
        style.id = 'mgl-editor-style';
        style.innerHTML = `
            :root {
                --border-color: #ddd;
                --bg-color: #f9f9f9;
                --accent: #007bff;
                --callout-bg: #fff8e1;
                --callout-border: #ffd54f;
                --editor-padding: 20px;
                --image-frame-padding: 6px;
                --block-gap: 10px;
                --block-indent: 28px;
            }
            .mgl-editor-scope * { box-sizing: border-box; }
            .mgl-editor-scope { height: 100%; min-height: 0; }
            .mgl-editor-scope .editor-container {
                max-width: 960px;
                margin: 0 auto;
                background: #fff;
                border: 1px solid var(--border-color);
                border-radius: 8px;
                box-shadow: 0 4px 6px rgba(0,0,0,0.05);
                overflow: hidden;
                display: flex;
                flex-direction: column;
                height: 100%;
            }
            .mgl-editor-scope .toolbar {
                display: flex; gap: 6px; padding: 10px 12px;
                background-color: var(--bg-color);
                border-bottom: 1px solid var(--border-color);
                flex-wrap: nowrap; align-items: center; flex-shrink: 0;
                overflow-x: auto; -webkit-overflow-scrolling: touch;
                scrollbar-width: none; -ms-overflow-style: none;
            }
            .mgl-editor-scope .toolbar::-webkit-scrollbar { display: none; }
            .mgl-editor-scope .toolbar-group {
                display: flex; gap: 4px; align-items: center; flex-shrink: 0;
                user-select: none; -webkit-user-select: none; -webkit-touch-callout: none;
            }
            .mgl-editor-scope .toolbar-sep { width: 1px; height: 22px; background: #ccc; margin: 0 4px; flex-shrink: 0; }
            .mgl-editor-scope .toolbar button {
                padding: 8px 12px; min-height: 36px; background: #fff; border: 1px solid var(--border-color);
                border-radius: 4px; cursor: pointer; font-size: 13px; white-space: nowrap;
                flex-shrink: 0; touch-action: manipulation;
            }
            .mgl-editor-scope .toolbar button:hover { background: #e9e9e9; }
            .mgl-editor-scope .toolbar button.active { background: #e7f1ff; border-color: var(--accent); color: var(--accent); }
            
            .mgl-editor-scope .image-size-controls { display: none; align-items: center; gap: 6px; font-size: 13px; color: #555; flex-shrink: 0; }
            .mgl-editor-scope .image-size-controls.visible { display: flex; }
            .mgl-editor-scope .image-size-controls input[type="number"] {
                width: 64px; padding: 4px 6px; border: 1px solid var(--border-color);
                border-radius: 4px; font-size: 16px;
            }
            
            /* ==========================================
               Mongolian vertical editing area
               ========================================== */
            .mgl-editor-scope .editor-content {
                writing-mode: vertical-lr;
                -webkit-writing-mode: vertical-lr;
                font-family: "Mongolian Baiti", "MenksoftQagan", "OyunQaganTig", sans-serif;
                font-size: 20px; line-height: 2; flex: 1; height: auto; min-height: 300px; width: 100%;
                padding: var(--editor-padding); overflow-y: hidden; overflow-x: auto;
                outline: none; text-align: left; cursor: text;
                overscroll-behavior-x: none; -webkit-overflow-scrolling: touch;
            }

            /* ==========================================
               Nested block scaffolding
               ========================================== */
            .mgl-editor-scope .block-wrapper { display: block; margin: 0; }
            .mgl-editor-scope .block-content {
                display: block; margin: 0 var(--block-gap) 0 0; padding: 0;
                outline: none; min-height: 1em; white-space: pre-wrap;
            }
            /* In vertical mode, "indent" = shift text downward via padding-top */
            .mgl-editor-scope .block-children {
                display: block; margin: 0;
                padding-top: var(--block-indent);
                border-top: 1px solid #ececec;
            }
            .mgl-editor-scope .block-children:empty { display: none; padding: 0; border: 0; }

            .mgl-editor-scope .editor-content h1 { font-size: 32px; font-weight: bold; }
            .mgl-editor-scope .editor-content h2 { font-size: 26px; font-weight: bold; }
            .mgl-editor-scope .editor-content h3 { font-size: 22px; font-weight: bold; }
            .mgl-editor-scope .editor-content blockquote {
                border-top: 3px solid #bbb; padding-top: 10px; color: #444;
            }
            .mgl-editor-scope .editor-content [data-block-type="list-item"] .list-marker {
                width: 6px; height: 6px; border-radius: 50%; background: #666;
            }
            .mgl-editor-scope .editor-content [data-block-type="ordered-list-item"] .list-marker {
                font-size: 13px; line-height: 1; font-family: sans-serif; color: #555;
            }
            .mgl-editor-scope .editor-content hr {
                border: none; width: 2px; height: 100%; background: #ccc; margin: 0 16px; padding: 0;
            }
            .mgl-editor-scope .editor-content .list-marker, .mgl-editor-scope .editor-content [data-block-type="task"] input[type="checkbox"],
            .mgl-editor-scope .editor-content .callout-icon, .mgl-editor-scope .editor-content .toggle-arrow {
                display: inline-block; writing-mode: horizontal-tb; -webkit-writing-mode: horizontal-tb;
                vertical-align: middle; margin: 0 0 8px 0; margin-inline-end: 8px; user-select: none;
            }
            .mgl-editor-scope .editor-content [data-block-type="task"] input[type="checkbox"] { cursor: pointer; }
            .mgl-editor-scope .editor-content [data-block-type="task"][data-checked="true"] > .block-content { text-decoration: line-through; color: #888; }
            .mgl-editor-scope .editor-content [data-block-type="callout"] {
                background: var(--callout-bg); border: 1px solid var(--callout-border);
                border-radius: 8px; padding: 12px; margin: 0 var(--block-gap) 0 0;
            }
            .mgl-editor-scope .editor-content [data-block-type="callout"] > .block-content { margin: 0; }
            .mgl-editor-scope .editor-content .callout-icon { font-size: 20px; line-height: 1; }
            .mgl-editor-scope .editor-content .toggle-arrow { cursor: pointer; color: #666; font-size: 16px; line-height: 1; }
            .mgl-editor-scope .editor-content [data-block-type="toggle"] .toggle-title { outline: none; min-height: 1em; font-weight: 600; }
            .mgl-editor-scope .editor-content [data-block-type="toggle"] .toggle-body { outline: none; min-height: 1em; opacity: 0.9; }
            .mgl-editor-scope .editor-content [data-block-type="toggle"][data-collapsed="true"] > .block-content .toggle-body,
            .mgl-editor-scope .editor-content [data-block-type="toggle"][data-collapsed="true"] > .block-children { display: none; }
            
            .mgl-editor-scope .editor-content [data-block-type="bookmark"] > .block-content {
                writing-mode: horizontal-tb; border: 1px solid #ddd; border-radius: 8px; padding: 12px;
                width: 220px; max-height: 100%; overflow: auto; background: #fff;
                box-shadow: 0 2px 4px rgba(0,0,0,0.05); cursor: default;
            }
            .mgl-editor-scope .editor-content [data-block-type="bookmark"] .bm-domain {
                width: 36px; height: 36px; border-radius: 50%; background: #e7f1ff; color: var(--accent);
                display: flex; align-items: center; justify-content: center; font-weight: bold; margin-bottom: 10px;
            }
            .mgl-editor-scope .editor-content [data-block-type="bookmark"] .bm-title { font-weight: 600; font-size: 14px; margin-bottom: 4px; word-break: break-word; }
            .mgl-editor-scope .editor-content [data-block-type="bookmark"] .bm-desc { font-size: 12px; color: #666; margin-bottom: 6px; word-break: break-word; }
            .mgl-editor-scope .editor-content [data-block-type="bookmark"] .bm-url { font-size: 11px; color: #1565c0; word-break: break-all; }
            
            .mgl-editor-scope .editor-content .editor-image {
                position: relative; writing-mode: horizontal-tb; height: auto; width: fit-content;
                max-height: 100%; padding: var(--image-frame-padding); cursor: pointer; display: block;
            }
            .mgl-editor-scope .editor-content .editor-image.selected { outline: 2px solid var(--accent); outline-offset: 2px; }
            .mgl-editor-scope .editor-content .editor-image img {
                display: block; max-height: 100%;
                border-radius: 4px; object-fit: fill; user-select: none; -webkit-user-drag: none;
            }
            .mgl-editor-scope .editor-content .editor-image .resize-handle {
                position: absolute; width: 20px; height: 20px; background: var(--accent); border: 1px solid #fff;
                border-radius: 2px; display: none; z-index: 2; touch-action: none;
            }
            .mgl-editor-scope .editor-content .editor-image.selected .resize-handle { display: block; }
            .mgl-editor-scope .editor-content .editor-image .resize-handle.nw { top: 0; left: 0; cursor: nwse-resize; }
            .mgl-editor-scope .editor-content .editor-image .resize-handle.ne { top: 0; right: 0; cursor: nesw-resize; }
            .mgl-editor-scope .editor-content .editor-image .resize-handle.sw { bottom: 0; left: 0; cursor: nesw-resize; }
            .mgl-editor-scope .editor-content .editor-image .resize-handle.se { bottom: 0; right: 0; cursor: nwse-resize; }
        `;
        document.head.appendChild(style);
    }

    // ==========================================
    // 2. Inject HTML (scoped class, no fixed ids — supports multiple instances)
    // ==========================================
    container.innerHTML = `
        <div class="mgl-editor-scope">
            <div class="editor-container">
                <div class="toolbar">
                    <div class="toolbar-group">
                        <button type="button" data-cmd="bold" title="Bold"><b>B</b></button>
                        <button type="button" data-cmd="italic" title="Italic"><i>I</i></button>
                        <button type="button" data-cmd="underline" title="Underline"><u>U</u></button>
                        <button type="button" data-action="link" title="Link">Link</button>
                    </div>
                    <div class="toolbar-sep"></div>
                    <div class="toolbar-group">
                        <button type="button" data-block="paragraph" title="Paragraph">Text</button>
                        <button type="button" data-block="heading-1" title="Heading 1">H1</button>
                        <button type="button" data-block="heading-2" title="Heading 2">H2</button>
                        <button type="button" data-block="heading-3" title="Heading 3">H3</button>
                    </div>
                    <div class="toolbar-sep"></div>
                    <div class="toolbar-group">
                        <button type="button" data-block="list-item" title="Bullet list">• List</button>
                        <button type="button" data-block="ordered-list-item" title="Numbered list">1. List</button>
                        <button type="button" data-block="task" title="Task">Task</button>
                        <button type="button" data-block="blockquote" title="Quote">Quote</button>
                    </div>
                    <div class="toolbar-sep"></div>
                    <div class="toolbar-group">
                        <button type="button" data-action="indent" title="Indent (Tab)">&raquo;</button>
                        <button type="button" data-action="outdent" title="Outdent (Shift+Tab)">&laquo;</button>
                    </div>
                    <div class="toolbar-sep"></div>
                    <div class="toolbar-group">
                        <button type="button" data-block="image" title="Image">Image</button>
                        <button type="button" data-block="divider" title="Divider">Divider</button>
                        <button type="button" data-block="bookmark" title="Bookmark">Bookmark</button>
                        <button type="button" data-block="callout" title="Callout">Callout</button>
                        <button type="button" data-block="toggle" title="Toggle">Toggle</button>
                    </div>
                    <div class="image-size-controls">
                        <label>W <input type="number" class="img-width" min="40" step="1"></label>
                        <label>H <input type="number" class="img-height" min="40" step="1"></label>
                        <label title="Keep aspect ratio">
                            <input type="checkbox" class="img-lock-ratio" checked> Lock
                        </label>
                    </div>
                    <button type="button" data-action="print-html" style="margin-left: auto; background:#007bff; color:#fff; border:none;">
                        Print HTML
                    </button>
                </div>
                <div class="editor-content" contenteditable="false" lang="mn-Mong" spellcheck="false"><div class="block-wrapper" data-block-type="paragraph"><p class="block-content" contenteditable="true">Type traditional Mongolian here...</p></div></div>
            </div>
        </div>
    `;

    // ==========================================
    // 3. Editor logic
    // ==========================================
    const editor = container.querySelector('.editor-content');
    const toolbar = container.querySelector('.toolbar');
    const sizeControls = container.querySelector('.image-size-controls');
    const widthInput = container.querySelector('.img-width');
    const heightInput = container.querySelector('.img-height');
    const lockRatioInput = container.querySelector('.img-lock-ratio');

    const MIN_SIZE = 40;
    const ZWSP = '\u200b';
    const MARKER_SELECTOR =
        '.list-marker, .callout-icon, .toggle-arrow, input[type="checkbox"]';
    const ATOMIC_TYPES = new Set(['image', 'divider', 'bookmark']);
    const SAFE_PROTOCOLS = new Set(['http:', 'https:', 'mailto:', 'tel:']);
    const URL_ATTRS = new Set(['href', 'src', 'data-url', 'action', 'formaction']);
    // Only these attrs are block-level; lift them onto the wrapper when migrating legacy data
    const BLOCK_STATE_ATTRS = ['checked', 'collapsed', 'index'];

    let selectedImage = null;
    let aspectRatio = 1;
    let resizing = null;
    let renumbering = false;

    function safeUrl(input, { allowDataImage = false } = {}) {
        const raw = String(input == null ? '' : input).trim();
        if (!raw) return null;
        let url;
        try {
            url = new URL(raw, window.location.href);
        } catch {
            return null;
        }
        if (SAFE_PROTOCOLS.has(url.protocol)) return url.href;
        if (allowDataImage && /^data:image\//i.test(url.href)) return url.href;
        return null;
    }

    function domainInitial(url) {
        try {
            return (new URL(url).hostname || '#').charAt(0).toUpperCase();
        } catch {
            return '#';
        }
    }

    function execCmd(command, value = null) {
        focusEditable(contentContainer(currentBlock()));
        document.execCommand(command, false, value);
        refreshToolbarState();
    }

    function markerSpan(className, content = '') {
        const span = document.createElement('span');
        span.className = className;
        span.textContent = content;
        return span;
    }

    function normalizeContentHtml(html) {
        return html.replace(/\u200b/g, '').replace(/(?:<br\s*\/?>)+$/i, '').trim();
    }

    // ------------------------------------------
    // Tree structure helpers
    // ------------------------------------------
    function contentOf(wrapper) {
        return wrapper ? wrapper.querySelector(':scope > .block-content') : null;
    }

    function childrenOf(wrapper, create = false) {
        if (!wrapper) return null;
        let box = wrapper.querySelector(':scope > .block-children');
        if (!box && create) {
            box = document.createElement('div');
            box.className = 'block-children';
            wrapper.appendChild(box);
        }
        return box;
    }

    function pruneChildren(wrapper) {
        const box = wrapper && wrapper.querySelector(':scope > .block-children');
        if (box && !box.children.length) box.remove();
    }

    /** Editable element that holds the caret: toggle uses its title; others use .block-content */
    function contentContainer(wrapper) {
        const content = contentOf(wrapper);
        if (!content) return wrapper;
        return content.querySelector(':scope > .toggle-title') || content;
    }

    function blockOf(node) {
        if (!node || node === editor || !editor.contains(node)) return null;
        const el = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
        const wrapper = el && el.closest('.block-wrapper');
        return wrapper && editor.contains(wrapper) ? wrapper : null;
    }

    /** Deepest last block — used as a fallback */
    function lastBlock(scope = editor) {
        const list = scope.querySelectorAll(':scope > .block-wrapper');
        const last = list[list.length - 1];
        if (!last) return null;
        const box = childrenOf(last);
        return (box && lastBlock(box)) || last;
    }

    function currentBlock() {
        const sel = window.getSelection();
        if (!sel || !sel.rangeCount) return lastBlock();
        const range = sel.getRangeAt(0);
        let node = range.startContainer;
        if (node.nodeType === Node.ELEMENT_NODE) {
            node = node.childNodes[range.startOffset] || node.lastChild || node;
        }
        return blockOf(node) || lastBlock();
    }

    /** Next / previous block in document order (DFS; skip collapsed subtrees) */
    function nextBlock(wrapper) {
        const box = childrenOf(wrapper);
        if (box && box.children.length && !isCollapsed(wrapper)) return box.firstElementChild;

        let node = wrapper;
        while (node) {
            const sibling = node.nextElementSibling;
            if (sibling && sibling.classList.contains('block-wrapper')) return sibling;
            const parentBox = node.parentElement;
            if (!parentBox || !parentBox.classList.contains('block-children')) return null;
            node = parentBox.parentElement;
        }
        return null;
    }

    function prevBlock(wrapper) {
        const sibling = wrapper.previousElementSibling;
        if (sibling && sibling.classList.contains('block-wrapper')) {
            let node = sibling;
            for (;;) {
                const box = childrenOf(node);
                if (box && box.children.length && !isCollapsed(node)) node = box.lastElementChild;
                else return node;
            }
        }
        const parentBox = wrapper.parentElement;
        if (parentBox && parentBox.classList.contains('block-children')) return parentBox.parentElement;
        return null;
    }

    function stepToEditable(wrapper, step) {
        let node = step(wrapper);
        while (node && isAtomic(node)) node = step(node);
        return node;
    }

    /** Caret targets within a block: toggle has title + body; others have one segment */
    function editableParts(wrapper) {
        const content = contentOf(wrapper);
        if (!content || isAtomic(wrapper)) return [];
        const title = content.querySelector(':scope > .toggle-title');
        if (!title) return [content];
        const body = content.querySelector(':scope > .toggle-body');
        return body && !isCollapsed(wrapper) ? [title, body] : [title];
    }

    function isNested(wrapper) {
        return !!wrapper && !!wrapper.parentElement &&
            wrapper.parentElement.classList.contains('block-children');
    }

    function isAtomic(wrapper) {
        return !!wrapper && wrapper.nodeType === Node.ELEMENT_NODE &&
            ATOMIC_TYPES.has(wrapper.dataset.blockType);
    }

    function isCollapsed(wrapper) {
        return !!wrapper && wrapper.dataset.collapsed === 'true';
    }

    function isBlockEmpty(wrapper) {
        const target = contentContainer(wrapper);
        if (target.querySelector('img')) return false;
        const clone = target.cloneNode(true);
        clone.querySelectorAll(MARKER_SELECTOR).forEach((n) => n.remove());
        return clone.textContent.replace(/\u200b/g, '').trim() === '';
    }

    /** Content-element HTML only (children excluded) so type changes keep the subtree */
    function blockContentHtml(wrapper) {
        const content = contentOf(wrapper);
        if (!content) return '';

        const clone = content.cloneNode(true);
        clone.querySelectorAll('.resize-handle').forEach((n) => n.remove());
        clone.querySelectorAll(MARKER_SELECTOR).forEach((n) => n.remove());

        const title = clone.querySelector('.toggle-title');
        if (!title) return normalizeContentHtml(clone.innerHTML);

        const body = clone.querySelector('.toggle-body');
        return [
            normalizeContentHtml(title.innerHTML),
            body ? normalizeContentHtml(body.innerHTML) : ''
        ].filter(Boolean).join('<br>');
    }

    // ------------------------------------------
    // Ordered-list numbering: count per level; nested levels keep a parent prefix
    // ------------------------------------------
    function renumberOrderedLists(scope = editor, prefix = '') {
        let n = 0;
        Array.from(scope.children).forEach((el) => {
            if (!el.classList || !el.classList.contains('block-wrapper')) return;

            let childPrefix = '';
            if (el.dataset.blockType === 'ordered-list-item') {
                n += 1;
                const path = prefix + n;
                el.dataset.index = String(n);
                el.dataset.path = path;
                childPrefix = path + '.';
                const marker = el.querySelector(':scope > .block-content .list-marker');
                const label = path + '.';
                if (marker && marker.textContent !== label) marker.textContent = label;
            } else {
                n = 0;
            }

            const box = childrenOf(el);
            if (box) renumberOrderedLists(box, childPrefix);
        });
    }

    function scheduleRenumber() {
        if (renumbering) return;
        renumbering = true;
        renumberOrderedLists();
        renumbering = false;
    }

    // ------------------------------------------
    // Caret
    // ------------------------------------------
    function focusEditable(el) {
        if (!el) return;
        const host = el.closest ? (el.closest('[contenteditable="true"]') || el) : el;
        if (typeof host.focus === 'function') host.focus({ preventScroll: true });
    }

    function setCaret(range) {
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        refreshToolbarState();
    }

    function placeCaretAtEnd(wrapper) {
        const target = contentContainer(wrapper);
        if (!target) return;
        focusEditable(target);
        const range = document.createRange();
        range.selectNodeContents(target);
        range.collapse(false);
        setCaret(range);
    }

    function placeCaretAtContentStart(wrapper) {
        const target = contentContainer(wrapper);
        if (!target) return;
        focusEditable(target);
        const zwsp = Array.from(target.childNodes).find(
            (n) => n.nodeType === Node.TEXT_NODE && n.data.startsWith(ZWSP)
        );
        const range = document.createRange();
        if (zwsp) range.setStart(zwsp, 1);
        else range.setStart(target, 0);
        range.collapse(true);
        setCaret(range);
    }

    function placeCaretInPart(part, atEnd) {
        focusEditable(part);
        const range = document.createRange();
        range.selectNodeContents(part);
        range.collapse(!atEnd);
        setCaret(range);
    }

    /** Preserve caret when moving a block: nodes are not rebuilt, so restore the old range */
    function snapshotCaret() {
        const sel = window.getSelection();
        if (!sel || !sel.rangeCount) return null;
        const r = sel.getRangeAt(0);
        return { sc: r.startContainer, so: r.startOffset, ec: r.endContainer, eo: r.endOffset };
    }

    function restoreCaret(snapshot, fallbackWrapper) {
        if (snapshot && editor.contains(snapshot.sc) && editor.contains(snapshot.ec)) {
            try {
                focusEditable(snapshot.sc.nodeType === Node.ELEMENT_NODE ? snapshot.sc : snapshot.sc.parentElement);
                const range = document.createRange();
                range.setStart(snapshot.sc, snapshot.so);
                range.setEnd(snapshot.ec, snapshot.eo);
                setCaret(range);
                return;
            } catch {
                /* Fall through to the fallback below */
            }
        }
        placeCaretAtEnd(fallbackWrapper);
    }

    /** Extract content between [boundary, caret] to detect start/end adjacency */
    function sliceAroundCaret(target, side) {
        const sel = window.getSelection();
        if (!sel.rangeCount || !sel.isCollapsed) return null;

        const caret = sel.getRangeAt(0);
        if (!target.contains(caret.startContainer) && caret.startContainer !== target) {
            return null;
        }

        const range = document.createRange();
        try {
            if (side === 'start') {
                range.setStart(target, 0);
                range.setEnd(caret.startContainer, caret.startOffset);
            } else {
                range.setStart(caret.startContainer, caret.startOffset);
                range.setEnd(target, target.childNodes.length);
            }
        } catch {
            return null;
        }

        const holder = document.createElement('div');
        holder.append(range.cloneContents());
        holder.querySelectorAll(MARKER_SELECTOR).forEach((n) => n.remove());
        return holder;
    }

    function caretAtStartOf(target) {
        const holder = sliceAroundCaret(target, 'start');
        return !!holder && !holder.querySelector('br, img') &&
            holder.textContent.replace(/\u200b/g, '') === '';
    }

    function caretAtEndOf(target) {
        const holder = sliceAroundCaret(target, 'end');
        // A trailing placeholder <br> is allowed
        return !!holder && !holder.querySelector('img') &&
            holder.querySelectorAll('br').length <= 1 &&
            holder.textContent.replace(/\u200b/g, '').trim() === '';
    }

    function caretAtContentStart(wrapper) {
        return caretAtStartOf(contentContainer(wrapper));
    }

    function extractTailHtml(wrapper) {
        const target = contentContainer(wrapper);
        const caret = window.getSelection().getRangeAt(0);
        const range = document.createRange();
        try {
            range.setStart(caret.startContainer, caret.startOffset);
            range.setEnd(target, target.childNodes.length);
        } catch {
            return '';
        }

        const holder = document.createElement('div');
        holder.append(range.extractContents());
        holder.querySelectorAll(MARKER_SELECTOR).forEach((n) => n.remove());
        if (!target.childNodes.length) target.appendChild(document.createElement('br'));
        return normalizeContentHtml(holder.innerHTML);
    }

    // ------------------------------------------
    // Block builders
    // ------------------------------------------
    const PLAIN_BLOCK_TAGS = {
        paragraph: 'p',
        'heading-1': 'h1',
        'heading-2': 'h2',
        'heading-3': 'h3',
        blockquote: 'blockquote'
    };

    const BLOCK_MARKERS = {
        'list-item': () => markerSpan('list-marker'),
        'ordered-list-item': () => markerSpan('list-marker'),
        callout: () => markerSpan('callout-icon', '💡'),
        task: () => {
            const box = document.createElement('input');
            box.type = 'checkbox';
            return box;
        }
    };

    const BLOCK_DATA = {
        task: { checked: 'false' },
        toggle: { collapsed: 'false' }
    };

    function buildContent(blockType, html) {
        if (blockType === 'divider') {
            return document.createElement('hr');
        }

        const el = document.createElement(PLAIN_BLOCK_TAGS[blockType] || 'div');

        if (PLAIN_BLOCK_TAGS[blockType]) {
            el.innerHTML = html || '<br>';
            return el;
        }

        if (blockType === 'toggle') {
            const title = document.createElement('div');
            title.className = 'toggle-title';
            const arrow = markerSpan('toggle-arrow', '▾');
            arrow.setAttribute('contenteditable', 'false');
            arrow.title = 'Collapse/expand';
            title.append(arrow, document.createTextNode(ZWSP));
            title.insertAdjacentHTML('beforeend', html || '');

            const body = document.createElement('div');
            body.className = 'toggle-body';
            body.innerHTML = '<br>';

            el.append(title, body);
            return el;
        }

        const marker = BLOCK_MARKERS[blockType]();
        marker.setAttribute('contenteditable', 'false');
        el.append(marker, document.createTextNode(ZWSP));
        el.insertAdjacentHTML('beforeend', html || '');
        return el;
    }

    function dressContent(blockType, el) {
        el.classList.add('block-content');
        el.setAttribute('contenteditable', ATOMIC_TYPES.has(blockType) ? 'false' : 'true');
        return el;
    }

    function wrapContent(blockType, contentEl) {
        const wrapper = document.createElement('div');
        wrapper.className = 'block-wrapper';
        wrapper.dataset.blockType = blockType;
        Object.assign(wrapper.dataset, BLOCK_DATA[blockType] || {});
        wrapper.append(dressContent(blockType, contentEl));
        return wrapper;
    }

    function buildBlock(blockType, html) {
        return wrapContent(blockType, buildContent(blockType, html));
    }

    /** Replace only the content element; children stay on the wrapper */
    function convertBlock(blockType, { caret = 'end', block = currentBlock() } = {}) {
        if (!block || isAtomic(block)) return null;

        const html = blockContentHtml(block);
        const oldContent = contentOf(block);
        const newContent = dressContent(blockType, buildContent(blockType, html));

        BLOCK_STATE_ATTRS.forEach((key) => { delete block.dataset[key]; });
        delete block.dataset.path;
        block.dataset.blockType = blockType;
        Object.assign(block.dataset, BLOCK_DATA[blockType] || {});

        if (oldContent) oldContent.replaceWith(newContent);
        else block.prepend(newContent);

        if (caret === 'start') placeCaretAtContentStart(block);
        else placeCaretAtEnd(block);
        return block;
    }

    // ------------------------------------------
    // Indent / outdent
    // ------------------------------------------
    function indentBlock(wrapper) {
        if (!wrapper) return false;
        const prev = wrapper.previousElementSibling;
        if (!prev || !prev.classList.contains('block-wrapper') || isAtomic(prev)) return false;

        const snapshot = snapshotCaret();
        childrenOf(prev, true).appendChild(wrapper);
        if (isCollapsed(prev)) {
            prev.dataset.collapsed = 'false';
            const arrow = prev.querySelector(':scope > .block-content .toggle-arrow');
            if (arrow) arrow.textContent = '▾';
        }
        restoreCaret(snapshot, wrapper);
        scheduleRenumber();
        return true;
    }

    function outdentBlock(wrapper) {
        if (!wrapper || !isNested(wrapper)) return false;

        const box = wrapper.parentElement;
        const parent = box.parentElement;
        const snapshot = snapshotCaret();

        // Following siblings become children so outdent preserves document order
        const following = [];
        let next = wrapper.nextElementSibling;
        while (next) {
            following.push(next);
            next = next.nextElementSibling;
        }

        parent.after(wrapper);
        if (following.length) childrenOf(wrapper, true).append(...following);
        pruneChildren(parent);

        restoreCaret(snapshot, wrapper);
        scheduleRenumber();
        return true;
    }

    // ------------------------------------------
    // Insert
    // ------------------------------------------
    const CONVERTIBLE = [
        'paragraph', 'heading-1', 'heading-2', 'heading-3', 'blockquote',
        'list-item', 'ordered-list-item', 'task', 'callout', 'toggle'
    ];

    const CONTINUING = new Set(['paragraph', 'list-item', 'ordered-list-item', 'task']);

    function insertBlockNode(node) {
        const target = currentBlock();
        const trailing = buildBlock('paragraph', '');

        if (target && target.dataset.blockType === 'paragraph' && isBlockEmpty(target)) {
            const box = childrenOf(target);
            target.replaceWith(node, trailing);
            if (box && box.children.length) trailing.appendChild(box);
        } else if (target) {
            target.after(node, trailing);
        } else {
            editor.append(node, trailing);
        }
        return trailing;
    }

    function bookmarkPart(className, text) {
        const el = document.createElement('div');
        el.className = className;
        el.textContent = text;
        return el;
    }

    const blockInserters = {
        divider() {
            placeCaretAtContentStart(insertBlockNode(buildBlock('divider', '')));
        },
        bookmark() {
            const input = prompt('Enter bookmark URL:', 'https://');
            if (input === null) return;
            const url = safeUrl(input);
            if (!url) {
                alert('Only http, https, mailto and tel links are allowed.');
                return;
            }
            const title = prompt('Title (optional):', url) || url;
            const desc = prompt('Description (optional):', '') || '';

            const card = document.createElement('div');
            card.dataset.url = url;
            card.dataset.title = title;
            card.dataset.desc = desc;
            card.append(
                bookmarkPart('bm-domain', domainInitial(url)),
                bookmarkPart('bm-title', title)
            );
            if (desc) card.append(bookmarkPart('bm-desc', desc));
            card.append(bookmarkPart('bm-url', url));

            placeCaretAtContentStart(insertBlockNode(wrapContent('bookmark', card)));
        },
        image() {
            insertImage();
        }
    };

    CONVERTIBLE.forEach((type) => {
        blockInserters[type] = () => convertBlock(type);
    });

    function insertLink() {
        const input = prompt('Enter link URL (http:// or https://):', 'https://');
        if (input === null) return;
        const url = safeUrl(input);
        if (!url) {
            alert('Only http, https, mailto and tel links are allowed.');
            return;
        }
        execCmd('createLink', url);
    }

    // ------------------------------------------
    // Images
    // ------------------------------------------
    const HANDLES = ['nw', 'ne', 'sw', 'se'];

    function ensureHandles(card) {
        if (card.querySelector('.resize-handle')) return;
        HANDLES.forEach((pos) => {
            const handle = document.createElement('span');
            handle.className = 'resize-handle ' + pos;
            handle.dataset.handle = pos;
            handle.setAttribute('contenteditable', 'false');
            card.appendChild(handle);
        });
    }

    function createImageBlock(url) {
        const card = document.createElement('div');
        card.className = 'editor-image';
        card.dataset.url = url;

        const img = document.createElement('img');
        img.src = url;
        img.alt = '';
        card.appendChild(img);
        ensureHandles(card);
        return wrapContent('image', card);
    }

    function imageSize(img) {
        return {
            w: parseFloat(img.style.width) || img.offsetWidth || MIN_SIZE,
            h: parseFloat(img.style.height) || img.offsetHeight || MIN_SIZE
        };
    }

    function constrainSize(width, height, keepRatio) {
        let w = width;
        let h = height;
        if (keepRatio && aspectRatio > 0) {
            w = Math.max(MIN_SIZE, w);
            h = w / aspectRatio;
            if (h < MIN_SIZE) {
                h = MIN_SIZE;
                w = h * aspectRatio;
            }
        }
        return { w: Math.max(MIN_SIZE, Math.round(w)), h: Math.max(MIN_SIZE, Math.round(h)) };
    }

    function applyImageSize(img, width, height) {
        const w = Math.max(MIN_SIZE, Math.round(width));
        const h = Math.max(MIN_SIZE, Math.round(height));
        img.style.width = w + 'px';
        img.style.height = h + 'px';
        const card = img.closest('.editor-image');
        if (card) {
            card.dataset.width = String(w);
            card.dataset.height = String(h);
        }
        widthInput.value = w;
        heightInput.value = h;
    }

    function rememberAspectRatio(img) {
        const { w, h } = imageSize(img);
        if (w > 0 && h > 0) aspectRatio = w / h;
    }

    function maxImageHeight() {
        const style = getComputedStyle(editor);
        const padding = parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
        const frame = 2 * parseFloat(
            style.getPropertyValue('--image-frame-padding')
        ) || 12;
        return Math.max(MIN_SIZE, editor.clientHeight - padding - frame);
    }

    function insertImage() {
        const input = prompt('Enter image URL:', 'https://');
        if (input === null) return;
        const url = safeUrl(input, { allowDataImage: true });
        if (!url) {
            alert('Only http, https and data:image URLs are allowed.');
            return;
        }

        const wrapper = createImageBlock(url);
        const card = contentOf(wrapper);
        const img = card.querySelector('img');
        applyImageSize(img, 150, 150);
        placeCaretAtContentStart(insertBlockNode(wrapper));

        const fit = () => {
            const naturalW = img.naturalWidth || 150;
            const naturalH = img.naturalHeight || 150;
            const maxH = maxImageHeight();
            let w = Math.min(naturalW, 200);
            let h = Math.round(w * (naturalH / naturalW));
            if (h > maxH) {
                h = maxH;
                w = Math.round(h * (naturalW / naturalH));
            }
            applyImageSize(img, w, h);
            selectImage(card);
        };

        img.addEventListener('load', fit, { once: true });
        if (img.complete && img.naturalWidth) fit();
    }

    function selectImage(card) {
        deselectImage();
        ensureHandles(card);
        selectedImage = card;
        card.classList.add('selected');
        sizeControls.classList.add('visible');

        const img = card.querySelector('img');
        const { w, h } = imageSize(img);
        widthInput.value = Math.round(w);
        heightInput.value = Math.round(h);
        rememberAspectRatio(img);
    }

    function deselectImage() {
        if (selectedImage) {
            selectedImage.classList.remove('selected');
            selectedImage = null;
        }
        sizeControls.classList.remove('visible');
    }

    // ------------------------------------------
    // Sanitize / hydrate / import-export
    // ------------------------------------------
    function sanitize(root) {
        root.querySelectorAll('script, style, iframe, object, embed, form, link, meta, base')
            .forEach((n) => n.remove());

        root.querySelectorAll('*').forEach((el) => {
            Array.from(el.attributes).forEach(({ name, value }) => {
                const lower = name.toLowerCase();
                if (lower.startsWith('on')) el.removeAttribute(name);
                else if (URL_ATTRS.has(lower) && !safeUrl(value, { allowDataImage: true })) {
                    el.removeAttribute(name);
                }
            });
        });
    }

    /** Upgrade legacy flat markup (and bare nodes from the browser) to wrapper/content */
    function migrateToTree(root) {
        Array.from(root.querySelectorAll('[data-block-type]')).forEach((el) => {
            if (el.classList.contains('block-wrapper')) return;
            if (el.closest('.block-content')) return;

            const type = el.dataset.blockType;
            const wrapper = document.createElement('div');
            wrapper.className = 'block-wrapper';
            wrapper.dataset.blockType = type;
            BLOCK_STATE_ATTRS.forEach((key) => {
                if (el.dataset[key] != null) wrapper.dataset[key] = el.dataset[key];
            });

            el.replaceWith(wrapper);
            delete el.dataset.blockType;
            wrapper.appendChild(dressContent(type, el));
        });

        normalizeContainer(root);
    }

    /** Strip indent whitespace from structural layers so vertical mode does not treat it as extra column width */
    function stripStructuralWhitespace(scope) {
        Array.from(scope.childNodes).forEach((node) => {
            if (node.nodeType === Node.TEXT_NODE && !node.data.trim()) node.remove();
            else if (node.nodeType === Node.COMMENT_NODE) node.remove();
        });
    }

    /** Only .block-wrapper nodes are allowed in the container; wrap other bare nodes as paragraphs */
    function normalizeContainer(scope) {
        stripStructuralWhitespace(scope);
        Array.from(scope.childNodes).forEach((node) => {
            if (node.nodeType === Node.ELEMENT_NODE && node.classList.contains('block-wrapper')) {
                stripStructuralWhitespace(node);
                const box = childrenOf(node);
                if (box) normalizeContainer(box);
                return;
            }
            if (node.nodeType === Node.TEXT_NODE || node.nodeType === Node.COMMENT_NODE) {
                node.remove();
                return;
            }
            const wrapper = buildBlock('paragraph', '');
            const content = contentOf(wrapper);
            content.innerHTML = '';
            node.replaceWith(wrapper);
            content.appendChild(node);
        });
    }

    function hydrate(root) {
        migrateToTree(root);

        root.querySelectorAll('.block-wrapper').forEach((wrapper) => {
            const content = contentOf(wrapper);
            if (!content) {
                wrapper.prepend(dressContent(wrapper.dataset.blockType || 'paragraph',
                    buildContent(wrapper.dataset.blockType || 'paragraph', '')));
                return;
            }
            dressContent(wrapper.dataset.blockType || 'paragraph', content);
            pruneChildren(wrapper);
        });

        root.querySelectorAll('.editor-image').forEach(ensureHandles);

        root.querySelectorAll(MARKER_SELECTOR).forEach((marker) => {
            marker.setAttribute('contenteditable', 'false');
            const next = marker.nextSibling;
            if (!next || next.nodeType !== Node.TEXT_NODE || !next.data.startsWith(ZWSP)) {
                marker.after(document.createTextNode(ZWSP));
            }
        });

        root.querySelectorAll('[data-block-type="toggle"]').forEach((toggle) => {
            const arrow = toggle.querySelector('.toggle-arrow');
            if (arrow) arrow.textContent = toggle.dataset.collapsed === 'true' ? '▸' : '▾';
        });

        root.querySelectorAll('[data-block-type="task"]').forEach((task) => {
            const box = task.querySelector('input[type="checkbox"]');
            if (!box) return;
            box.checked = task.dataset.checked === 'true';
            box.toggleAttribute('checked', box.checked);
        });
    }

    function getCleanHtml() {
        const clone = editor.cloneNode(true);
        clone.querySelectorAll('.resize-handle').forEach((n) => n.remove());
        clone.querySelectorAll('.editor-image').forEach((n) => n.classList.remove('selected'));
        clone.querySelectorAll('.block-children').forEach((n) => { if (!n.children.length) n.remove(); });
        clone.querySelectorAll('[contenteditable]').forEach((n) => n.removeAttribute('contenteditable'));
        return clone.innerHTML.replace(/\u200b/g, '').trim();
    }

    /** Recursively export nested JSON for backends / cross-platform rendering */
    function getJson(scope = editor) {
        return Array.from(scope.children)
            .filter((el) => el.classList && el.classList.contains('block-wrapper'))
            .map((el) => {
                const node = {
                    type: el.dataset.blockType || 'paragraph',
                    html: blockContentHtml(el),
                    children: []
                };
                if (el.dataset.checked != null) node.checked = el.dataset.checked === 'true';
                if (el.dataset.collapsed != null) node.collapsed = el.dataset.collapsed === 'true';
                if (el.dataset.path != null) node.number = el.dataset.path;

                const content = contentOf(el);
                if (content && content.dataset.url) node.url = content.dataset.url;
                if (content && content.dataset.title) node.title = content.dataset.title;
                if (content && content.dataset.desc) node.desc = content.dataset.desc;

                const box = childrenOf(el);
                if (box) node.children = getJson(box);
                return node;
            });
    }

    function setHtml(html) {
        const template = document.createElement('template');
        template.innerHTML = String(html == null ? '' : html);
        sanitize(template.content);
        hydrate(template.content);

        deselectImage();
        editor.replaceChildren(template.content);
        if (!editor.querySelector(':scope > .block-wrapper')) editor.append(buildBlock('paragraph', ''));
        scheduleRenumber();
        refreshToolbarState();
    }

    function printHtml() {
        const html = getCleanHtml();
        console.log('------------------- Editor content -------------------');
        console.log(html);
        alert('HTML has been printed to the console (F12)');
    }

    function snapshotSelection() {
        const sel = window.getSelection();
        if (!sel || !sel.rangeCount) return null;
        const range = sel.getRangeAt(0);
        return { sel, range: range.cloneRange(), collapsed: range.collapsed };
    }

    function restoreSelection(snap) {
        if (!snap || snap.collapsed) return;
        if (snap.sel.rangeCount && !snap.sel.isCollapsed) return;
        try {
            snap.sel.removeAllRanges();
            snap.sel.addRange(snap.range);
        } catch {
            /* range detached */
        }
    }

    function refreshToolbarState() {
        const sel = window.getSelection();
        const inEditor = !!sel && sel.rangeCount > 0 && editor.contains(sel.anchorNode);
        const snap = inEditor ? snapshotSelection() : null;
        const block = inEditor ? currentBlock() : null;
        const type = block && block.nodeType === Node.ELEMENT_NODE ? block.dataset.blockType : null;

        toolbar.querySelectorAll('button[data-cmd]').forEach((btn) => {
            let on = false;
            try {
                on = inEditor && document.queryCommandState(btn.dataset.cmd);
            } catch {
                on = false;
            }
            btn.classList.toggle('active', !!on);
        });

        toolbar.querySelectorAll('button[data-block]').forEach((btn) => {
            btn.classList.toggle('active', !!type && btn.dataset.block === type);
        });

        // queryCommandState can collapse a range that starts at offset 0
        // inside a vertical-lr contenteditable (first glyph).
        restoreSelection(snap);
    }

    // ------------------------------------------
    // Events
    // ------------------------------------------
    toolbar.addEventListener('mousedown', (e) => {
        if (e.target.closest('button')) e.preventDefault();
    });

    toolbar.addEventListener('click', (e) => {
        const btn = e.target.closest('button');
        if (!btn) return;

        if (btn.dataset.cmd) {
            execCmd(btn.dataset.cmd);
            return;
        }
        if (btn.dataset.action === 'link') {
            insertLink();
            return;
        }
        if (btn.dataset.action === 'indent') {
            indentBlock(currentBlock());
            refreshToolbarState();
            return;
        }
        if (btn.dataset.action === 'outdent') {
            outdentBlock(currentBlock());
            refreshToolbarState();
            return;
        }
        if (btn.dataset.action === 'print-html') {
            printHtml();
            return;
        }
        if (btn.dataset.block && blockInserters[btn.dataset.block]) {
            blockInserters[btn.dataset.block]();
            refreshToolbarState();
        }
    });

    function insertBreak() {
        const sel = window.getSelection();
        if (!sel.rangeCount) return false;

        if (!sel.isCollapsed) {
            const range = sel.getRangeAt(0);
            if (blockOf(range.startContainer) !== blockOf(range.endContainer)) return false;
            document.execCommand('delete');
        }

        const block = currentBlock();
        if (!block || isAtomic(block) || !block.dataset.blockType) return false;

        const type = block.dataset.blockType;

        if (type === 'toggle') {
            const body = block.querySelector(':scope > .block-content .toggle-body');
            const caretNode = window.getSelection().getRangeAt(0).startContainer;
            if (body && !body.contains(caretNode) && caretNode !== body) {
                block.dataset.collapsed = 'false';
                const arrow = block.querySelector(':scope > .block-content .toggle-arrow');
                if (arrow) arrow.textContent = '▾';
                placeCaretInPart(body, true);
            } else {
                appendAfter(block, buildBlock('paragraph', ''));
            }
            return true;
        }

        // Empty nested block: Enter = outdent one level
        if (isBlockEmpty(block) && isNested(block) && outdentBlock(block)) return true;

        if (CONTINUING.has(type) && type !== 'paragraph' && isBlockEmpty(block)) {
            convertBlock('paragraph', { caret: 'start', block });
            return true;
        }

        const tail = extractTailHtml(block);
        appendAfter(block, buildBlock(CONTINUING.has(type) ? type : 'paragraph', tail));
        return true;
    }

    function handleEnter(e) {
        const sel = window.getSelection();
        if (!sel.rangeCount) return;

        if (!sel.isCollapsed) {
            const range = sel.getRangeAt(0);
            if (blockOf(range.startContainer) !== blockOf(range.endContainer)) return;
        }

        const block = currentBlock();
        if (!block || isAtomic(block) || !block.dataset.blockType) return;

        e.preventDefault();
        insertBreak();
    }

    /**
     * With expanded children, insert the new block as the first child; otherwise as the next sibling.
     * Keeps the caret on the visually adjacent next line.
     */
    function appendAfter(block, next) {
        const box = childrenOf(block);
        if (box && box.children.length && !isCollapsed(block)) box.prepend(next);
        else block.after(next);
        placeCaretAtContentStart(next);
        scheduleRenumber();
        return next;
    }

    /** Merge the current block into the end of the previous block (subtree moves with it) */
    function mergeIntoPrevious(block, prev) {
        const target = contentContainer(prev);
        const source = blockContentHtml(block);
        if (!target) return false;

        const holder = document.createElement('div');
        holder.innerHTML = source;

        if (target.lastChild && target.lastChild.nodeName === 'BR') target.lastChild.remove();

        const seam = document.createTextNode('');
        target.append(seam, ...Array.from(holder.childNodes));

        const box = childrenOf(block);
        if (box && box.children.length) {
            childrenOf(prev, true).append(...Array.from(box.children));
        }
        const parentBox = block.parentElement;
        block.remove();
        if (parentBox && parentBox.classList.contains('block-children') && !parentBox.children.length) {
            parentBox.remove();
        }

        if (!target.childNodes.length) target.appendChild(document.createElement('br'));

        focusEditable(target);
        const range = document.createRange();
        range.setStart(seam, 0);
        range.collapse(true);
        setCaret(range);
        scheduleRenumber();
        return true;
    }

    /**
     * Each .block-content is its own contenteditable, so the browser will not move the caret out.
     * At boundaries we move it into the adjacent block. In vertical mode ArrowDown/Up are inline forward/back.
     */
    function handleArrow(e) {
        const sel = window.getSelection();
        if (!sel.rangeCount || !sel.isCollapsed) return;

        const block = currentBlock();
        if (!block) return;
        const parts = editableParts(block);
        const node = sel.getRangeAt(0).startContainer;
        const index = parts.findIndex((part) => part === node || part.contains(node));
        if (index === -1) return;

        if (e.key === 'ArrowDown') {
            if (!caretAtEndOf(parts[index])) return;
            if (index + 1 < parts.length) {
                e.preventDefault();
                placeCaretInPart(parts[index + 1], false);
                return;
            }
            const next = stepToEditable(block, nextBlock);
            if (!next) return;
            e.preventDefault();
            placeCaretAtContentStart(next);
            return;
        }

        if (!caretAtStartOf(parts[index])) return;
        if (index > 0) {
            e.preventDefault();
            placeCaretInPart(parts[index - 1], true);
            return;
        }
        const prev = stepToEditable(block, prevBlock);
        if (!prev) return;
        e.preventDefault();
        placeCaretAtEnd(prev);
    }

    function deleteAtBoundary() {
        const block = currentBlock();
        if (!block || isAtomic(block) || !block.dataset.blockType) return false;
        // Empty new paragraphs only have a placeholder <br>; treat that as
        // "at start" so IME backspace can merge the line away.
        if (!caretAtContentStart(block) && !isBlockEmpty(block)) return false;

        if (block.dataset.blockType !== 'paragraph') {
            convertBlock('paragraph', { caret: 'start', block });
            return true;
        }

        const prev = block.previousElementSibling;

        if (!prev) {
            if (isNested(block)) return Boolean(outdentBlock(block));
            return false;
        }

        if (isAtomic(prev)) {
            if (contentOf(prev) === selectedImage) deselectImage();
            const box = childrenOf(prev);
            if (box && box.children.length) prev.replaceWith(...Array.from(box.children));
            else prev.remove();
            scheduleRenumber();
            return true;
        }
        mergeIntoPrevious(block, prev);
        return true;
    }

    function handleBackspace(e) {
        if (!deleteAtBoundary()) return;
        e.preventDefault();
    }

    editor.addEventListener('keydown', (e) => {
        if (e.isComposing || e.keyCode === 229) return;

        if (e.key === 'Tab') {
            e.preventDefault();
            const block = currentBlock();
            if (!block) return;
            if (e.shiftKey) outdentBlock(block);
            else indentBlock(block);
            return;
        }
        if (e.key === 'Enter') {
            if (e.shiftKey) {
                e.preventDefault();
                document.execCommand('insertLineBreak');
                return;
            }
            handleEnter(e);
            return;
        }
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
            handleArrow(e);
            return;
        }
        if (e.key === 'Backspace') handleBackspace(e);
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') deselectImage();
    });

    editor.addEventListener('click', (e) => {
        const arrow = e.target.closest('.toggle-arrow');
        if (arrow) {
            const toggle = arrow.closest('[data-block-type="toggle"]');
            const collapsed = toggle.dataset.collapsed === 'true';
            toggle.dataset.collapsed = collapsed ? 'false' : 'true';
            arrow.textContent = collapsed ? '▾' : '▸';
            e.preventDefault();
            return;
        }

        if (e.target.matches('input[type="checkbox"]')) {
            const task = e.target.closest('[data-block-type="task"]');
            if (task) task.dataset.checked = e.target.checked ? 'true' : 'false';
            e.target.toggleAttribute('checked', e.target.checked);
            return;
        }

        const card = e.target.closest('.editor-image');
        if (card && editor.contains(card)) {
            e.preventDefault();
            selectImage(card);
            return;
        }
        deselectImage();

        // Outer container is not editable; clicking empty space moves the caret
        // into the nearest block. In vertical-lr the first glyph sits against
        // this padding, so a drag that includes it mouseups here — keep the range.
        if (e.target === editor || e.target.classList.contains('block-children') ||
            e.target.classList.contains('block-wrapper')) {
            const sel = window.getSelection();
            if (sel && !sel.isCollapsed && editor.contains(sel.anchorNode)) return;
            const block = e.target === editor ? lastBlock() : blockOf(e.target);
            if (block && !isAtomic(block)) placeCaretAtEnd(block);
        }
    });

    function getEventPoint(e) {
        if (e.touches && e.touches.length > 0) return e.touches[0];
        if (e.changedTouches && e.changedTouches.length > 0) return e.changedTouches[0];
        return e;
    }

    function handleResizeStart(e) {
        const handle = e.target.closest('.resize-handle');
        if (!handle) return;
        e.preventDefault();
        e.stopPropagation();

        const card = handle.closest('.editor-image');
        const img = card.querySelector('img');
        selectImage(card);
        const { w, h } = imageSize(img);
        const point = getEventPoint(e);
        resizing = {
            handle: handle.dataset.handle,
            startX: point.clientX,
            startY: point.clientY,
            startW: w,
            startH: h,
            img
        };
    }

    function handleResizeMove(e) {
        if (!resizing) return;
        if (e.cancelable) e.preventDefault();

        const point = getEventPoint(e);
        const dx = point.clientX - resizing.startX;
        const dy = point.clientY - resizing.startY;
        const dir = resizing.handle;
        let width = resizing.startW;
        let height = resizing.startH;

        if (dir.includes('e')) width = resizing.startW + dx;
        if (dir.includes('w')) width = resizing.startW - dx;
        if (dir.includes('s')) height = resizing.startH + dy;
        if (dir.includes('n')) height = resizing.startH - dy;

        const lock = lockRatioInput.checked;
        if (lock) {
            if (Math.abs(dx) >= Math.abs(dy)) height = width / aspectRatio;
            else width = height * aspectRatio;
        }

        const size = constrainSize(width, height, lock);
        applyImageSize(resizing.img, size.w, size.h);
    }

    function handleResizeEnd() {
        if (!resizing) return;
        if (!lockRatioInput.checked) rememberAspectRatio(resizing.img);
        resizing = null;
    }

    editor.addEventListener('mousedown', handleResizeStart);
    editor.addEventListener('touchstart', handleResizeStart, { passive: false });

    document.addEventListener('mousedown', (e) => {
        if (!editor.contains(e.target) && !toolbar.contains(e.target)) deselectImage();
    });

    document.addEventListener('mousemove', handleResizeMove);
    document.addEventListener('touchmove', handleResizeMove, { passive: false });

    document.addEventListener('mouseup', handleResizeEnd);
    document.addEventListener('touchend', handleResizeEnd);
    document.addEventListener('touchcancel', handleResizeEnd);

    function applyFromInputs(driver) {
        if (!selectedImage) return;
        const img = selectedImage.querySelector('img');
        const lock = lockRatioInput.checked;
        let w = parseFloat(widthInput.value) || MIN_SIZE;
        let h = parseFloat(heightInput.value) || MIN_SIZE;

        if (lock) {
            if (driver === 'width') h = w / aspectRatio;
            else w = h * aspectRatio;
        }

        const size = constrainSize(w, h, lock);
        applyImageSize(img, size.w, size.h);
        if (!lock) rememberAspectRatio(img);
    }

    widthInput.addEventListener('change', () => applyFromInputs('width'));
    heightInput.addEventListener('change', () => applyFromInputs('height'));

    editor.addEventListener('paste', (e) => {
        e.preventDefault();
        const clipboard = e.clipboardData || window.clipboardData;
        const text = clipboard ? clipboard.getData('text/plain') : '';
        if (text) document.execCommand('insertText', false, text);
    });

    document.addEventListener('selectionchange', refreshToolbarState);

    new MutationObserver(() => scheduleRenumber())
        .observe(editor, { childList: true, subtree: true });

    hydrate(editor);
    renumberOrderedLists();
    refreshToolbarState();

    // ==========================================
    // 4. Public API
    // ==========================================
    return {
        getHtml: getCleanHtml,
        setHtml: setHtml,
        getJson: () => getJson(editor),
        insertBreak,
        deleteAtBoundary,
        indent: () => indentBlock(currentBlock()),
        outdent: () => outdentBlock(currentBlock()),
        focus: () => {
            const block = editor.querySelector(':scope > .block-wrapper');
            if (block) placeCaretAtEnd(block);
        }
    };
}
