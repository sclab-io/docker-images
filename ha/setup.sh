#!/bin/bash

find . -type f -exec sed -i 's/ip1/0.0.0.0/g' {} +
find . -type f -exec sed -i 's/ip2/0.0.0.0/g' {} +
find . -type f -exec sed -i 's|your-domain.com|real-domain.com|g' {} +
find . -type f -exec sed -i 's|https://your-domain.com|https://real-domain.com|g' {} +
find . -type f -exec sed -i 's|changeThisQdrantApiKey|changeThisQdrantApiKey|g' {} +
find . -type f -exec sed -i 's|changeThisRedisPassword|changeThisRedisPassword|g' {} +
find . -type f -exec sed -i 's|changeThisMongoPassword|changeThisMongoPassword|g' {} +
