db = db.getSiblingDB('testapp');

db.createCollection('items');

db.items.insertMany([
  { name: 'Initial Item 1', createdAt: new Date() },
  { name: 'Initial Item 2', createdAt: new Date() }
]);
