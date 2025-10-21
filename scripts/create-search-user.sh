#!/bin/bash

# Create MongoDB Search Sync User
# Run this after deploying mongot to create the required user in MongoDB

set -e

SEARCH_PASSWORD="${SEARCH_SYNC_PASSWORD:-changeme}"

echo "Creating search-sync-source user in MongoDB..."
echo ""

docker exec -it mongodb-enterprise mongosh -u admin -p password123 --authenticationDatabase admin --eval "
use admin

// Create the search sync user
try {
  db.createUser({
    user: 'search-sync-source',
    pwd: '${SEARCH_PASSWORD}',
    roles: [
      { role: 'searchCoordinator', db: 'admin' }
    ]
  })
  print('✅ User search-sync-source created successfully')
} catch (e) {
  if (e.code === 51003) {
    print('⚠️  User search-sync-source already exists')
  } else {
    print('❌ Error creating user: ' + e.message)
    throw e
  }
}

// Verify user exists
print('')
print('Verifying user...')
const users = db.getUsers({ filter: { user: 'search-sync-source' } })
if (users && users.users && users.users.length > 0) {
  print('✅ User search-sync-source exists with roles:')
  printjson(users.users[0].roles)
} else {
  print('❌ User not found')
}
"

echo ""
echo "Done! The search-sync-source user is ready."
echo ""

