const test = require('node:test');
const assert = require('node:assert/strict');
const { createStockLedger, quantity } = require('../src/repositories/stock-ledger.repository');
const { createInventoryRepository } = require('../src/repositories/inventory.repository');

function fixture() {
  let state = {
    warehouse: { inventory_item_id: 1, barcode: 'sku', unit: 'box', category_id: 2, stock: 999 },
    shelf: { product_id: 2, barcode: 'sku', unit: 'box', category_id: 2, stock: 999 },
    entries: [
      { ledger_id: 1, event_key: 'initial-w', location: 'warehouse', inventory_item_id: 1, delta: 10 },
      { ledger_id: 2, event_key: 'initial-s', location: 'shelf', product_id: 2, delta: 4 },
    ],
  };
  let snapshot;
  let failShelf = false;
  const connection = {
    async beginTransaction() { snapshot = structuredClone(state); },
    async commit() { snapshot = null; },
    async rollback() { state = snapshot; },
    release() {},
    async execute(sql, p = []) {
      if (sql.startsWith('SELECT * FROM inventory_items')) return [[state.warehouse]];
      if (sql.startsWith('SELECT * FROM products')) return [[state.shelf]];
      if (sql.startsWith('SELECT delta')) {
        const field = p[1] === 'warehouse' ? 'inventory_item_id' : 'product_id';
        return [state.entries.filter(e => e.location === p[1] && e[field] === p[0])];
      }
      if (sql.includes('WHERE event_key')) return [state.entries.filter(e => e.event_key === p[0])];
      if (sql.includes("kind = 'sale'")) return [state.entries.filter(e => e.order_id === p[0] && e.kind === 'sale')];
      if (sql.includes('INSERT INTO inventory_ledger')) {
        if (failShelf && p[2] === 'shelf') throw new Error('simulated shelf failure');
        const fields = ['event_key','operation_id','location','inventory_item_id','product_id','delta','kind','actor_id','order_id','note'];
        state.entries.push({ ledger_id: state.entries.length + 1, ...Object.fromEntries(fields.map((f,i)=>[f,p[i]])) });
        return [{ insertId: state.entries.length }];
      }
      if (sql.startsWith('UPDATE products SET stock')) { state.shelf.stock = p[0]; return [{}]; }
      if (sql.startsWith('UPDATE inventory_items SET stock')) { state.warehouse.stock = p[0]; return [{}]; }
      throw new Error('Unexpected SQL: ' + sql);
    },
  };
  return { connection, pool: { getConnection: async () => connection }, state: () => state,
    failShelf: () => { failShelf = true; } };
}

test('quantity rejects fractions, invalid values and overflow', () => {
  for (const value of [null, undefined, '', true, -1, 1.5, Infinity, NaN, 2147483648])
    assert.throws(() => quantity(value));
  assert.equal(quantity('12'), 12);
  assert.equal(quantity(-12, {signed:true}), -12);
});

test('ledger is authoritative, updates projection and rejects overselling', async () => {
  const f = fixture(); const ledger = createStockLedger(f.connection);
  assert.equal((await ledger.balance('shelf', 2)).total, 4);
  await ledger.post({ location:'shelf', id:2, delta:-3, kind:'sale', eventKey:'sale:1:2', orderId:1 });
  assert.equal(f.state().shelf.stock, 1);
  await assert.rejects(ledger.post({ location:'shelf', id:2, delta:-2, kind:'sale' }), /Không đủ/);
  assert.equal(f.state().entries.length, 3);
});

test('replay is idempotent and changed payload conflicts', async () => {
  const f = fixture(); const ledger = createStockLedger(f.connection);
  const entry = { location:'warehouse', id:1, delta:3, kind:'receipt', eventKey:'same' };
  await ledger.post(entry); await ledger.post(entry);
  assert.equal(f.state().entries.length, 3);
  await assert.rejects(ledger.post({...entry, delta:4}), /thao tác khác/);
});

test('adjustment uses ledger balance, not stale cached stock', async () => {
  const f = fixture(); await createStockLedger(f.connection).set('warehouse',1,7,5);
  assert.equal(f.state().entries.at(-1).delta,-3);
  assert.equal(f.state().warehouse.stock,7);
});

test('atomic transfer and retry preserve total stock', async () => {
  const f = fixture(); const repo = createInventoryRepository(f.pool);
  const transfer = () => repo.transaction(tx => tx.exportStock(1,3,2,5,'request-0123456789'));
  await transfer(); await transfer();
  assert.equal(f.state().warehouse.stock,7);
  assert.equal(f.state().shelf.stock,7);
  assert.equal(f.state().entries.length,4);
  assert.equal(f.state().entries.at(-1).operation_id, f.state().entries.at(-2).operation_id);
});

test('second transfer leg failure rolls back first leg and projection', async () => {
  const f = fixture(); const original=structuredClone(f.state()); f.failShelf();
  await assert.rejects(createInventoryRepository(f.pool).transaction(tx=>tx.exportStock(1,3,2,5,'request-0123456789')));
  assert.deepEqual(f.state(),original);
});

test('transfer rejects mismatched unit before any writes', async () => {
  const f=fixture(); f.state().shelf.unit='piece';
  await assert.rejects(createInventoryRepository(f.pool).transaction(tx=>tx.exportStock(1,3,2,5)), /không khớp/);
  assert.equal(f.state().entries.length,2);
});

test('sale reversal restores only once', async () => {
  const f=fixture(); const ledger=createStockLedger(f.connection);
  await ledger.post({location:'shelf',id:2,delta:-3,kind:'sale',orderId:8,eventKey:'sale:8:2'});
  await ledger.reverseOrder(8,5); await ledger.reverseOrder(8,5);
  assert.equal(f.state().shelf.stock,4);
  assert.equal(f.state().entries.filter(e=>e.kind==='sale_reversal').length,1);
});

test('runtime stock projection writes stay centralized', () => {
  const fs=require('node:fs'); const path=require('node:path');
  function walk(dir) {
    for(const entry of fs.readdirSync(dir,{withFileTypes:true})) {
      const file=path.join(dir,entry.name);
      if(entry.isDirectory()) walk(file);
      else if(file.endsWith('.js') && !file.endsWith('stock-ledger.repository.js'))
        assert.doesNotMatch(fs.readFileSync(file,'utf8'), /UPDATE\s+(?:products|inventory_items)\s+SET\s+stock\s*=/i, file);
    }
  }
  walk(path.join(__dirname,'../src'));
});
