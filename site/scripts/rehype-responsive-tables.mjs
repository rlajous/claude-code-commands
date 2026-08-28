/** Return direct element children, optionally restricted to one HTML tag. */
function elements(node, tagName) {
  if (!node || !Array.isArray(node.children)) return [];
  return node.children.filter((child) => child.type === 'element' && (!tagName || child.tagName === tagName));
}

/** Return the readable text carried by one HTML AST node. */
function nodeText(node) {
  if (!node || typeof node !== 'object') return '';
  if (node.type === 'text' && typeof node.value === 'string') return node.value;
  if (node.type === 'element' && node.tagName === 'img' && typeof node.properties?.alt === 'string') return node.properties.alt;
  return Array.isArray(node.children) ? node.children.map(nodeText).join('') : '';
}

/** Merge static HTML properties without discarding metadata from earlier plugins. */
function setProperties(node, properties) {
  node.properties = { ...(node.properties ?? {}), ...properties };
}

/** Walk an HTML AST in document order and visit every node exactly once. */
function walk(node, visitor) {
  visitor(node);
  if (!Array.isArray(node.children)) return;
  for (const child of node.children) walk(child, visitor);
}

/**
 * Add native labels, explicit roles, and one stable value wrapper to Markdown
 * tables so narrow layouts can reflow without splitting mixed inline content.
 */
export default function responsiveTables() {
  return (tree) => {
    walk(tree, (table) => {
      if (table.type !== 'element' || table.tagName !== 'table') return;
      const headerGroup = elements(table, 'thead')[0];
      const bodyGroup = elements(table, 'tbody')[0];
      const header = elements(headerGroup, 'tr')[0];
      if (!header || !bodyGroup) return;

      const headerCells = elements(header, 'th');
      const labels = headerCells.map((cell, index) => nodeText(cell).trim() || `Column ${index + 1}`);
      setProperties(table, {
        'data-responsive-table': '',
        'data-columns': String(labels.length),
        role: 'table',
      });
      setProperties(header, { role: 'row' });
      headerCells.forEach((cell) => setProperties(cell, { role: 'columnheader', scope: 'col' }));

      for (const row of elements(bodyGroup, 'tr')) {
        setProperties(row, { role: 'row' });
        elements(row, 'td').forEach((cell, index) => {
          setProperties(cell, {
            'data-label': labels[index] ?? `Column ${index + 1}`,
            ...(index === 0 ? { 'data-primary': 'true' } : {}),
            role: 'cell',
          });
          cell.children = [{
            type: 'element',
            tagName: 'div',
            properties: { className: ['table-cell-value'] },
            children: cell.children,
          }];
        });
      }
    });
  };
}
