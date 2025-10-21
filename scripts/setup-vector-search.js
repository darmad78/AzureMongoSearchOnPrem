// MongoDB Enterprise Vector Search Index Setup
// Run this script to create the vector search index for semantic search

// Connect to the database
use searchdb;

// Create a vector search index on the documents collection
// Note: This requires MongoDB Atlas or MongoDB Enterprise with Atlas Search deployed

print("Setting up MongoDB Enterprise Vector Search...");

// For MongoDB Enterprise with Atlas Search, you would create the index like this:
// This is typically done through mongosh or the Atlas UI

const indexDefinition = {
    name: "vector_index",
    type: "vectorSearch",
    definition: {
        fields: [
            {
                type: "vector",
                path: "embedding",
                numDimensions: 384,  // Matches all-MiniLM-L6-v2 model
                similarity: "cosine"
            },
            {
                type: "filter",
                path: "tags"
            },
            {
                type: "filter",
                path: "source"
            }
        ]
    }
};

print("Vector Search Index Definition:");
printjson(indexDefinition);

// Instructions for creating the index:
print("\n📋 To create this index:");
print("\n1. If using MongoDB Atlas:");
print("   - Go to Atlas UI → Database → Search");
print("   - Click 'Create Search Index'");
print("   - Choose 'JSON Editor'");
print("   - Paste the index definition above");
print("\n2. If using MongoDB Enterprise with Atlas Search:");
print("   - Ensure Atlas Search is deployed with your cluster");
print("   - Use the Atlas CLI or API to create the index");
print("\n3. For this Docker demo:");
print("   - The backend will fall back to manual vector search");
print("   - Full vector search requires Atlas Search deployment");

print("\n✅ Index configuration ready!");
print("🔍 384 dimensions (all-MiniLM-L6-v2)");
print("📊 Cosine similarity metric");
print("🏷️  Filters on: tags, source");

// Create some sample indexes for demo
print("\n\nCreating text search indexes for demo...");

db.documents.createIndex(
    { title: "text", body: "text", tags: "text" },
    { name: "text_search_index" }
);

print("✅ Text search index created!");

// Create standard indexes for performance
db.documents.createIndex({ tags: 1 });
db.documents.createIndex({ source: 1 });
db.documents.createIndex({ "embedding": 1 });

print("✅ Standard indexes created!");

print("\n🎉 Setup complete!");
print("\nNote: MongoDB Vector Search ($vectorSearch) requires:");
print("  - MongoDB Atlas OR");
print("  - MongoDB Enterprise with Atlas Search nodes");
print("\nFor full demo, deploy using the Kubernetes script (deploy.sh)");
print("or use MongoDB Atlas.");

