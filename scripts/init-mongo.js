// MongoDB initialization script
db = db.getSiblingDB('searchdb');

// Create a user for the application
db.createUser({
  user: 'searchuser',
  pwd: 'searchpass',
  roles: [
    {
      role: 'readWrite',
      db: 'searchdb'
    }
  ]
});

// Create the documents collection with text index
db.createCollection('documents');

// Create text index for full-text search
db.documents.createIndex({
  "title": "text",
  "body": "text", 
  "tags": "text"
}, {
  name: "text_index"
});

// Insert some sample documents for testing
db.documents.insertMany([
  {
    title: "Introduction to MongoDB",
    body: "MongoDB is a NoSQL database that stores data in flexible, JSON-like documents. It's designed for scalability and flexibility.",
    tags: ["database", "nosql", "mongodb"]
  },
  {
    title: "Python FastAPI Guide",
    body: "FastAPI is a modern, fast web framework for building APIs with Python. It's based on standard Python type hints.",
    tags: ["python", "api", "web", "framework"]
  },
  {
    title: "React Development Tips",
    body: "React is a JavaScript library for building user interfaces. It uses components and a virtual DOM for efficient rendering.",
    tags: ["react", "javascript", "frontend", "ui"]
  }
]);

print("Database initialized successfully!");
print("Sample documents inserted for testing.");
