#!/bin/sh
set -eu

: "${MONGO_CHAT_USER:?MONGO_CHAT_USER is required}"
: "${MONGO_CHAT_PASSWORD:?MONGO_CHAT_PASSWORD is required}"

mongosh --quiet "mongodb://$MONGO_INITDB_ROOT_USERNAME:$MONGO_INITDB_ROOT_PASSWORD@127.0.0.1:27017/admin" \
  --eval 'const dbChat = db.getSiblingDB("chatdb"); if (!dbChat.getUser(process.env.MONGO_CHAT_USER)) { dbChat.createUser({user: process.env.MONGO_CHAT_USER, pwd: process.env.MONGO_CHAT_PASSWORD, roles: [{role:"readWrite", db:"chatdb"}]}); }'
